#lang racket
(require "conditionals.rkt")
(require "interp.rkt")
(provide compile-S2 vectors-passes)

(define compile-S2
  (class compile-S1
    (super-new)

    (define/override (primitives)
      (set-union (super primitives) 
		 (set 'vector 'vector-ref 'vector-set!)))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; type-check : env -> S2 -> S2
    (define/override (type-check env)
      (lambda (e)
	(match e
	   [`(vector ,es ...)
	    `(Vector ,@(map (send this type-check env) es))]
	   [`(vector-ref ,e-vec ,i)
	    (define t ((send this type-check env) e-vec))
	    (match t
               [`(Vector ,ts ...)
		(unless (i . < . (length ts))
			(error "index too large for vector-ref:" i))
		(list-ref ts i)]
	       [else (error "expected a vector in vector-ref, not" t)])]
	   [`(vector-set! ,e-vec ,i ,e-arg)
	    (define t ((send this type-check env) e-vec))
	    (define t-arg ((send this type-check env) e-arg))
	    (match t
               [`(Vector ,ts ...)
		(unless (i . < . (length ts))
			(error "index too large for vector-set!:" i))
		(unless (equal? (list-ref ts i) t-arg)
			(error "type mismatch in vector-set!" 
			       (list-ref ts i) t-arg)) ]
	       [else (error "expected a vector in vector-set!, not" t)])]
	   [`(eq? ,e1 ,e2)
	    (match `(,((send this type-check env) e1)
		     ,((send this type-check env) e2))
	       [`((Vector ,ts1 ...) (Vector ,ts2 ...))
		'Boolean]
	       [else ((super type-check env) e)])]
	   [else ((super type-check env) e)]
	   )))

    ;; nothing to do for uniquify
    ;; nothing to do for flatten

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; select-instructions : C2 -> psuedo-x86

    (define/override (select-instructions)
      (lambda (e)
	(match e
	   [`(assign ,lhs (vector ,es ...))
	    (define new-lhs ((send this select-instructions) lhs))
	    (define new-es (map (send this select-instructions) es))
	    (define n (length es))
	    (define initializers
	      (for/list ([e new-es] [i (in-range 0 (length new-es))])
			`(mov ,e (offset ,new-lhs ,i))))
	    (append `((mov (int ,(* n 8)) (register rdi))
		      (call _malloc)
		      (mov (register rax) ,new-lhs))
		    initializers)]
	   [`(assign ,lhs (vector-ref ,e-vec ,i))
	    (define new-lhs ((send this select-instructions) lhs))
	    (define new-e-vec ((send this select-instructions) e-vec))
	    `((mov (offset ,new-e-vec ,i) ,new-lhs))]
	   [`(assign ,lhs (vector-set! ,e-vec ,i ,e-arg))
	    (define new-lhs ((send this select-instructions) lhs))
	    (define new-e-vec ((send this select-instructions) e-vec))
	    (define new-e-arg ((send this select-instructions) e-arg))
	    `((mov ,new-e-arg (offset ,new-e-vec ,i)))]
	   [else ((super select-instructions) e)]
	   )))
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; assign-locations : homes -> pseudo-x86 -> pseudo-x86
    (define/override (assign-locations homes)
      (lambda (e)
	(match e
	   [`(offset ,e ,i)
	    (define new-e ((assign-locations homes) e))
	    `(offset ,new-e ,i)]
	   [else ((super assign-locations homes) e)]
	   )))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; insert-spill-code : psuedo-x86 -> x86

    (define/override (on-stack? a)
      (match a
	 [`(offset ,e ,i) (send this on-stack? e)]
	 [else #f]))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; print-x86 : x86 -> string
    (define/override (print-x86)
      (lambda (e)
	(match e
	   [`(offset ,e ,i) (format "~a(~a)" i ((send this print-x86) e))]
	   [else ((super print-x86) e)]
	   )))

    ));; compile-S2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Passes
(define vectors-passes
  (let ([compiler (new compile-S2)]
	[interp (new interp-S2)])
    (list `("programify" ,(lambda (ast) `(program () ,ast))
	    ,(send interp interp-scheme '()))
	  `("type-check" ,(send compiler type-check '())
	    ,(send interp interp-scheme '()))
	  `("uniquify" ,(send compiler uniquify '())
	    ,(send interp interp-scheme '()))
	  `("flatten" ,(send compiler flatten #f)
	    ,(send interp interp-C '()))
	  `("instruction selection" ,(send compiler select-instructions)
	    ,(send interp interp-x86 '()))
	  `("liveness analysis" ,(send compiler uncover-live (void))
	    ,(send interp interp-x86 '()))
	  `("build interference" ,(send compiler build-interference
	   				(void) (void))
	    ,(send interp interp-x86 '()))
	  `("allocate registers" ,(send compiler allocate-registers)
	    ,(send interp interp-x86 '()))
	  `("insert spill code" ,(send compiler insert-spill-code)
	    ,(send interp interp-x86 '()))
	  `("print x86" ,(send compiler print-x86) #f)
	  )))
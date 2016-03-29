Red/System [
	Title:   "Bignum! datatype runtime functions"
	Author:  "bitbegin"
	File: 	 %bignum.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2015 Nenad Rakocevic & Qingtian Xie & bitbegin. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

bignum: context [
	verbose: 1
	
	ciL:				4				;-- bignum! unit is 4 bytes; chars in limb
	biL:				ciL << 3		;-- bits in limb
	biLH:				ciL << 2		;-- half bits in limb
	BN_MAX_LIMB:		25600			;-- support 25600 bytes * 4 = 819200 bits
	
	;--- Actions ---

	push: func [
		big [red-bignum!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/push"]]

		copy-cell as red-value! big stack/push*
	]
	
	serialize: func [
		big		[red-bignum!]
		buffer	[red-string!]
		only?	[logic!]
		all?	[logic!]
		flat?	[logic!]
		arg		[red-value!]
		part	[integer!]
		mold?	[logic!]
		return: [integer!]
		/local
			s      [series!]
			bytes  [integer!]
			head   [byte-ptr!]
			tail   [byte-ptr!]
			size   [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/serialize"]]

		s: GET_BUFFER(big)
		head: (as byte-ptr! s/offset)
		tail: as byte-ptr! s/tail
		size: as-integer tail - head

		bytes: 0
		if size > 30 [
			string/append-char GET_BUFFER(buffer) as-integer lf
			part: part - 1
		]
		
		if big/sign = -1 [
			string/append-char GET_BUFFER(buffer) as-integer #"-"
			bytes: bytes + 1
		]
		
		part: part - 2
		while [head < tail][
			tail: tail - 1
			string/concatenate-literal buffer string/byte-to-hex as-integer tail/value
			bytes: bytes + 1
			if bytes % 32 = 0 [
				string/append-char GET_BUFFER(buffer) as-integer lf
				part: part - 1
			]
			part: part - 2
			if all [OPTION?(arg) part <= 0][return part]
		]
		if all [size > 30 bytes % 32 <> 0] [
			string/append-char GET_BUFFER(buffer) as-integer lf
			part: part - 1
		]
		part - 1
	]
	
	append-int: func [
		big			[red-bignum!]
		i			[integer!]
		/local
			s	 	[series!]
			p	 	[byte-ptr!]
			p4	 	[int-ptr!]
	][
		s: GET_BUFFER(big)
		p: alloc-tail-unit s 4		
		p4: as int-ptr! p
		p4/value: i
	]
	
	grow: func [
		big			[red-bignum!]
		size		[integer!]
		/local
			s	 	[series!]
	][
		if size > BN_MAX_LIMB [--NOT_IMPLEMENTED--]
		
		s: GET_BUFFER(big)
		if size > s/size [
			s: expand-series s (size * 4)
		]
	]
	
	clamp: func [
		big	 		[red-bignum!]
		/local
			s	 	[series!]
			head	[int-ptr!]
			tail	[int-ptr!]
			p4		[int-ptr!]
	][
		s: GET_BUFFER(big)
		head: as int-ptr! s/offset
		tail: as int-ptr! s/tail
		
		while [true] [
			either head <> tail [
				p4: tail - 1
				either p4/1 <> 0 [
					break
				][
					tail: tail - 1
				]
			][
				break
			]
		]
		s/tail: as cell! tail
	]
	
	absolute-compare: func [
		big1	 	[red-bignum!]
		big2	 	[red-bignum!]
		return:	 	[integer!]
		/local
			s1	 	[series!]
			s2	 	[series!]
			tail1	[int-ptr!]
			tail2	[int-ptr!]
			size 	[integer!]
	][
		s1: GET_BUFFER(big1)
		s2: GET_BUFFER(big2)
		if (s1/tail - s1/offset) > (s2/tail - s2/offset) [return 1]
		if (s1/tail - s1/offset) < (s2/tail - s2/offset) [return -1]
		
		tail1: as int-ptr! s1/tail
		tail2: as int-ptr! s2/tail
		size: as integer! s1/tail - s1/offset
		loop size [
			tail1: tail1 - 1
			tail2: tail2 - 1
			if tail1/1 > tail2/1 [return 1]
			if tail1/1 < tail2/1 [return -1]
		]
		return 0
	]
	
	compare: func [
		big1	 	[red-bignum!]
		big2	 	[red-bignum!]
		return:	 	[integer!]
	][
		if all [
			big1/sign = 1
			big2/sign = -1
		][
			return 1
		]
		
		if all [
			big2/sign = 1
			big1/sign = -1
		][
			return -1
		]
		
		either big1/sign = 1 [
			return absolute-compare big1 big2
		][
			return absolute-compare big2 big1
		]
	]
	
	make: func [
		proto	 [red-value!]
		spec	 [red-value!]
		return:	 [red-bignum!]
		/local
			big	 [red-bignum!]
			size [integer!]
			int	 [red-integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/make"]]
		
		size: 1
		switch TYPE_OF(spec) [
			TYPE_INTEGER [
				int: as red-integer! spec
				size: int/value
			]
			default [--NOT_IMPLEMENTED--]
		]
		if size > BN_MAX_LIMB [--NOT_IMPLEMENTED--]
		big: as red-bignum! stack/arguments;stack/push*
		big/header: TYPE_BIGNUM							;-- implicit reset of all header flags
		big/node: 	alloc-series size 4 0				;-- alloc 4 bytes unit buffer
		big/sign: 	1									;-- default sign is "+"
		big
	]

	mold: func [
		big		[red-bignum!]
		buffer	[red-string!]
		only?	[logic!]
		all?	[logic!]
		flat?	[logic!]
		arg		[red-value!]
		part	[integer!]
		indent	[integer!]
		return:	[integer!]
		/local
			formed [c-string!]
			s	   [series!]
			unit   [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/mold"]]
		
		serialize big buffer only? all? flat? arg part yes
	]
	
	compare*: func [
		value1    [red-bignum!]						;-- first operand
		value2    [red-bignum!]						;-- second operand
		op	      [integer!]						;-- type of comparison
		return:   [integer!]
		/local
			res	  [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/compare"]]

		if all [
			op = COMP_STRICT_EQUAL
			TYPE_OF(value1) <> TYPE_OF(value2)
		][return 1]
		
		switch op [
			COMP_EQUAL		[res: compare value1 value2]
			COMP_NOT_EQUAL 	[res: not compare value1 value2]
			default [
				res: SIGN_COMPARE_RESULT(value1 value2)
			]
		]
		res
	]
	
	absolute: func [
		return: [red-bignum!]
		/local
			big	  [red-bignum!]
			value [float!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/absolute"]]

		big: as red-bignum! stack/arguments
		big/sign: 1
		big 											;-- re-use argument slot for return value
	]
	
	complement: func [
		big		[red-bignum!]
		return:	[red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/complement"]]
		
		either big/sign = 1 [
			big/sign: -1
		][
			big/sign: 1
		]
		as red-value! big
	]
	
	swap: func [
		big1	 	[red-bignum!]
		big2	 	[red-bignum!]
		return:	 	[red-bignum!]
		/local
			node 	[node!]
			sign 	[integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "bignum/swap"]]
		
		node: big1/node 
		sign: big1/sign
		big1/node: big2/node
		big1/sign: big2/sign
		big2/node: node
		big2/sign: sign
		big1
	]
	
	init: does [
		datatype/register [
			TYPE_BIGNUM
			TYPE_VALUE
			"bignum!"
			;-- General actions --
			:make
			null			;random
			null			;reflect
			null			;to
			null			;form
			:mold
			null			;eval-path
			null			;set-path
			:compare*
			;-- Scalar actions --
			:absolute
			null			;add
			null			;divide
			null			;multiply
			null			;negate
			null			;power
			null			;remainder
			null			;round
			null			;subtract
			null			;even?
			null			;odd?
			;-- Bitwise actions --
			null			;and~
			:complement
			null			;or~
			null			;xor~
			;-- Series actions --
			null			;append
			null			;at
			null			;back
			null			;change
			null			;clear
			null			;copy
			null			;find
			null			;head
			null			;head?
			null			;index?
			null			;insert
			null			;length?
			null			;next
			null			;pick
			null			;poke
			null			;put
			null			;remove
			null			;reverse
			null			;select
			null			;sort
			null			;skip
			:swap
			null			;tail
			null			;tail?
			null			;take
			null			;trim
			;-- I/O actions --
			null			;create
			null			;close
			null			;delete
			null			;modify
			null			;open
			null			;open?
			null			;query
			null			;read
			null			;rename
			null			;update
			null			;write
		]
	]
]

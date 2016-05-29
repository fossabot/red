Red/System [
	Title:   "Map! datatype runtime functions"
	Author:  "Qingtian Xie"
	File:	 %map.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2014-2015 Qingtian Xie. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

map: context [
	verbose: 0

	rs-length?: func [
		map 	[red-hash!]
		return: [integer!]
		/local
			s	 [series!]
			size [int-ptr!]
	][
		s: as series! map/table/value
		size: as int-ptr! s/offset
		size/value
	]

	serialize: func [
		map		[red-hash!]
		buffer	[red-string!]
		only?	[logic!]
		all?	[logic!]
		flat?	[logic!]
		arg		[red-value!]
		part	[integer!]
		indent?	[logic!]
		tabs	[integer!]
		mold?	[logic!]
		return: [integer!]
		/local
			s		[series!]
			value	[red-value!]
			next	[red-value!]
			s-tail	[red-value!]
			blank	[byte!]
	][
		if positive? rs-length? map [
			either flat? [
				indent?: no
				blank: space
			][
				if mold? [
					string/append-char GET_BUFFER(buffer) as-integer lf
					part: part - 1
				]
				blank: lf
			]

			s: GET_BUFFER(map)
			value: s/offset
			s-tail: s/tail
			cycles/push map/node
			
			while [value < s-tail][
				next: value + 1
				unless TYPE_OF(next) = TYPE_NONE [
					if indent? [part: object/do-indent buffer tabs part]

					part: actions/mold value buffer only? all? flat? arg part tabs
					string/append-char GET_BUFFER(buffer) as-integer space
					part: part - 1
					
					unless cycles/detect? value buffer :part mold? [
						part: actions/mold next buffer only? all? flat? arg part tabs
					]

					if any [indent? next + 1 < s-tail][			;-- no final LF when FORMed
						string/append-char GET_BUFFER(buffer) as-integer blank
						part: part - 1
					]
				]
				if all [OPTION?(arg) part <= 0][
					cycles/pop
					return part
				]
				value: value + 2
			]
			cycles/pop
		]
		part
	]
	
	extend: func [
		map		[red-hash!]
		spec	[red-block!]
		case?	[logic!]
		return: [red-value!]
		/local
			src		[red-block!]
			cell	[red-value!]
			tail	[red-value!]
			value	[red-value!]
			int		[red-integer!]
			s		[series!]
			cnt		[integer!]
			size	[integer!]
			table	[node!]
			key		[red-value!]
			val		[red-value!]
			psize	[int-ptr!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/extend"]]

		src: as red-block! spec
		size: block/rs-length? src

		s: GET_BUFFER(map)
		size: as-integer s/tail + size - s/offset
		if size > s/size [s: expand-series s size]

		s: GET_BUFFER(src)
		cell: s/offset + src/head
		tail: s/tail

		table: map/table
		while [cell < tail][
			key: _hashtable/get table cell 0 0 case? no no
			value: cell + 1
			either TYPE_OF(value) = TYPE_NONE [			;-- delete key entry
				val: key + 1
				if all [
					key <> null
					TYPE_OF(val) <> TYPE_NONE
				][
					_hashtable/delete table key
				]
			][
				either key = null [
					key: copy-cell cell as cell! alloc-at-tail as red-block! map
					_hashtable/put table key
				][
					val: key + 1
					if TYPE_OF(val) = TYPE_NONE [		;-- increase size of keys
						s: as series! table/value
						psize: as int-ptr! s/offset
						psize/value: psize/value + 1
					]
				]
				copy-cell value key + 1
			]
			cell: cell + 2
		]
		as red-value! map
	]
	
	push: func [
		map [red-hash!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/push"]]

		copy-cell as red-value! map stack/push*
	]
	
	make-at: func [
		slot	[red-value!]
		blk		[red-block!]
		size	[integer!]
		return:	[red-hash!]
		/local
			table [node!]
			map	  [red-hash!]
	][
		if blk = null [blk: block/make-at as red-block! slot size]
		table: _hashtable/init size blk HASH_TABLE_MAP 1
		map: as red-hash! slot
		map/header: TYPE_MAP							;-- implicit reset of all header flags
		map/table: table
		map
	]

	;--- Actions ---

	make: func [
		proto		[red-value!]
		spec		[red-value!]
		return:		[red-hash!]
		/local
			map		[red-hash!]
			size	[integer!]
			int		[red-integer!]
			blk		[red-block!]
			blk?	[logic!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/make"]]

		blk?: no
		size: 1
		switch TYPE_OF(spec) [
			TYPE_INTEGER [
				int: as red-integer! spec
				size: int/value
				if negative? size [fire [TO_ERROR(script out-of-range) spec]]
			]
			TYPE_BLOCK [
				size: block/rs-length? as red-block! spec
				if size % 2 <> 0 [fire [TO_ERROR(script invalid-arg) spec]]
				blk?: yes
			]
			default [--NOT_IMPLEMENTED--]
		]
		if zero? size [size: 1]
		blk: block/make-at as red-block! stack/push* size
		if blk? [block/copy as red-block! spec blk null no null]
		make-at as red-value! blk blk size
	]

	reflect: func [
		map		[red-hash!]
		field	[integer!]
		return:	[red-block!]
		/local
			blk    [red-block!]
			s-tail [red-value!]
			value  [red-value!]
			next   [red-value!]
			new   [red-value!]
			size   [integer!]
			s	   [series!]
	][
		blk: 		as red-block! stack/push*
		blk/header: TYPE_BLOCK
		blk/head: 	0

		s: GET_BUFFER(map)
		value: s/offset
		s-tail: s/tail
		size: block/rs-length? as red-block! map
		case [
			field = words/words [
				blk/node: alloc-cells size >> 1
				while [value < s-tail][
					next: value + 1
					unless TYPE_OF(next) = TYPE_NONE [
						new: block/rs-append blk value
						if TYPE_OF(value) = TYPE_SET_WORD [
							new/header: TYPE_WORD
						]
					]
					value: value + 2
				]
			]
			field = words/values [
				blk/node: alloc-cells size >> 1
				while [value < s-tail][
					next: value + 1
					unless TYPE_OF(next) = TYPE_NONE [
						block/rs-append blk next
					]
					value: value + 2
				]
			]
			field = words/body [
				blk/node: alloc-cells size
				while [value < s-tail][
					next: value + 1
					unless TYPE_OF(next) = TYPE_NONE [
						block/rs-append blk value
						block/rs-append blk next
					]
					value: value + 2
				]
			]
			true [
				--NOT_IMPLEMENTED--						;@@ raise error
			]
		]
		as red-block! stack/set-last as red-value! blk
	]

	form: func [
		map		  [red-hash!]
		buffer	  [red-string!]
		arg		  [red-value!]
		part 	  [integer!]
		return:   [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/form"]]

		serialize map buffer no no no arg part no 0 no
	]

	mold: func [
		map		[red-hash!]
		buffer	[red-string!]
		only?	[logic!]
		all?	[logic!]
		flat?	[logic!]
		arg		[red-value!]
		part	[integer!]
		indent	[integer!]
		return:	[integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/mold"]]

		string/concatenate-literal buffer "#("
		part: serialize map buffer only? all? flat? arg part - 2 yes indent + 1 yes
		if indent > 0 [part: object/do-indent buffer indent part]
		string/append-char GET_BUFFER(buffer) as-integer #")"
		part - 1
	]

	compare: func [
		map1	   [red-hash!]							;-- first operand
		map2	   [red-hash!]							;-- second operand
		op		   [integer!]							;-- type of comparison
		return:	   [integer!]
		/local type res
	][
		#if debug? = yes [if verbose > 0 [print-line "map/compare"]]

		type: TYPE_OF(map2)
		if type <> TYPE_MAP [RETURN_COMPARE_OTHER]
		switch op [
			COMP_EQUAL
			COMP_STRICT_EQUAL
			COMP_NOT_EQUAL
			COMP_SORT
			COMP_CASE_SORT [
				res: block/compare-each as red-block! map1 as red-block! map2 op
			]
			default [
				res: -2
			]
		]
		res
	]

	eval-path: func [
		parent	[red-hash!]							;-- implicit type casting
		element	[red-value!]
		value	[red-value!]
		path	[red-value!]
		case?	[logic!]
		return:	[red-value!]
		/local
			table	[node!]
			key		[red-value!]
			val		[red-value!]
			s		[series!]
			size	[int-ptr!]
	][
		table: parent/table
		key: _hashtable/get table element 0 0 case? no no

		either value <> null [						;-- set value
			either TYPE_OF(value) = TYPE_NONE [		;-- delete key entry
				val: key + 1
				if all [
					key <> null
					TYPE_OF(val) <> TYPE_NONE
				][
					_hashtable/delete table key
				]
				value
			][
				either key = null [
					key: copy-cell element as cell! alloc-at-tail as red-block! parent
					_hashtable/put table key
				][
					val: key + 1
					if TYPE_OF(val) = TYPE_NONE [	;-- increase size of keys
						s: as series! table/value
						size: as int-ptr! s/offset
						size/value: size/value + 1
					]
				]
				copy-cell value key + 1
			]
		][
			either key = null [none-value][key + 1]
		]
	]

	;--- Reading actions ---

	;pick: func [
	;	map		[red-hash!]
	;	index	[red-value!]
	;	boxed	[red-value!]
	;	return:	[red-value!]
	;][
	;	#if debug? = yes [if verbose > 0 [print-line "map/pick"]]
	;
	;	eval-path map boxed null as red-value! none-value no
	;]

	;--- Modifying actions ---
	
	put: func [
		map		[red-hash!]
		field	[red-value!]
		value	[red-value!]
		case?	[logic!]
		return:	[red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/put"]]
		
		eval-path map field value as red-value! none-value case?
		value
	]

	clear: func [
		map		[red-hash!]
		return:	[red-value!]
		/local
			s	[series!]
			value [red-value!]
			i     [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/clear"]]

		s: GET_BUFFER(map)
		i: 0
		while [
			value: s/offset + i
			value < s/tail
		][
			_hashtable/delete map/table value
			i: i + 2
		]
		as red-value! map
	]

	;poke: func [
	;	map		[red-hash!]
	;	index	[red-value!]
	;	data	[red-value!]
	;	boxed	[red-value!]
	;	return:	[red-value!]
	;][
	;	#if debug? = yes [if verbose > 0 [print-line "map/poke"]]
	;
	;	eval-path map boxed data as red-value! none-value no
	;]

	;--- Property reading actions ---

	length?: func [
		map		[red-hash!]
		return: [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/length?"]]

		rs-length? map
	]
	
	find: func [
		map			[red-hash!]
		value		[red-value!]
		part		[red-value!]
		only?		[logic!]
		case?		[logic!]
		any?		[logic!]
		with-arg	[red-string!]
		skip		[red-integer!]
		last?		[logic!]
		reverse?	[logic!]
		tail?		[logic!]
		match?		[logic!]
		return:		[red-value!]
		/local
			table [node!]
			key   [red-value!]
			val   [red-value!]
	][
		table: map/table
		key: _hashtable/get table value 0 0 case? no no
		val: key + 1
		either any [key = null TYPE_OF(val) = TYPE_NONE][none-value][true-value]
	]

	;--- Navigation actions ---

	select: func [
		map		 [red-hash!]
		value	 [red-value!]
		part	 [red-value!]
		only?	 [logic!]
		case?	 [logic!]
		any?	 [logic!]
		with-arg [red-string!]
		skip	 [red-integer!]
		last?	 [logic!]
		reverse? [logic!]
		return:	 [red-value!]
		/local
			table [node!]
			key   [red-value!]
	][
		table: map/table
		key: _hashtable/get table value 0 0 case? no no
		either key = null [none-value][key + 1]
	]

	;--- Misc actions ---

	set-many: func [
		blk		[red-block!]
		map		[red-hash!]
		size	[integer!]
		/local
			w		[red-word!]
			k		[red-value!]
			v		[red-value!]
			i		[integer!]
			type	[integer!]
	][
		i: 1
		k: block/rs-head as red-block! map
		w: as red-word! block/rs-head blk
		while [i <= size][
			either i % 2 = 0 [
				_context/set w k
			][
				v: k + 1
				unless TYPE_OF(v) = TYPE_NONE [
					type: TYPE_OF(w)
					unless any [
						type = TYPE_WORD
						type = TYPE_GET_WORD
						type = TYPE_SET_WORD
						type = TYPE_LIT_WORD
					][
						fire [TO_ERROR(script invalid-arg) w]
					]
					type: k/header
					k/header: TYPE_WORD
					_context/set w k
					k/header: type
				]
			]
			k: k + 1
			w: w + 1
			i: i + 1
		]
	]

	copy: func [
		map	    	[red-hash!]
		new			[red-hash!]
		part-arg	[red-value!]
		deep?		[logic!]
		types		[red-value!]
		return:		[red-hash!]
	][
		#if debug? = yes [if verbose > 0 [print-line "map/copy"]]
		new: as red-hash! block/clone as red-block! map deep? yes

		new/header: TYPE_MAP
		new/table: 	_hashtable/copy map/table new/node
		new
	]

	init: does [
		datatype/register [
			TYPE_MAP
			TYPE_VALUE
			"map!"
			;-- General actions --
			:make
			null			;random
			:reflect
			null			;to
			:form
			:mold
			:eval-path
			null			;set-path
			:compare
			;-- Scalar actions --
			null			;absolute
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
			null			;complement
			null			;or~
			null			;xor~
			;-- Series actions --
			null			;append
			null			;at
			null			;back
			null			;change
			:clear
			:copy
			:find
			null			;head
			null			;head?
			null			;index?
			null			;insert
			:length?
			null			;move
			null			;next
			null			;pick
			null			;poke
			:put
			null			;remove
			null			;reverse
			:select
			null			;sort
			null			;skip
			null			;swap
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
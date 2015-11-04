Red/System [
	Title:	"Windows GUI backend"
	Author: "Nenad Rakocevic, Xie Qingtian"
	File: 	%gui.reds
	Tabs: 	4
	Rights: "Copyright (C) 2015 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#include %win32.reds
#include %classes.reds
#include %events.reds

#include %font.reds
#include %para.reds
#include %camera.reds
#include %image.reds
#include %menu.reds
#include %panel.reds
#include %tab-panel.reds
#include %text-list.reds
#include %button.reds
#include %draw.reds

hScreen:		as handle! 0
hInstance:		as handle! 0
default-font:	as handle! 0
hover-saved:	as handle! 0							;-- last window under mouse cursor
version-info: 	declare OSVERSIONINFO
current-msg: 	as tagMSG 0
wc-extra:		80										;-- reserve 64 bytes for win32 internal usage (arbitrary)
wc-offset:		60										;-- offset to our 16+4 bytes

log-pixels-x:	0
log-pixels-y:	0
screen-size-x:	0
screen-size-y:	0

kb-state: 		allocate 256							;-- holds keyboard state for keys conversion

clean-up: does [
	current-msg: null
]

get-face-values: func [
	hWnd	[handle!]
	return: [red-value!]
	/local
		ctx	 [red-context!]
		node [node!]
		s	 [series!]
][
	node: as node! GetWindowLong hWnd wc-offset + 4
	ctx: TO_CTX(node)
	s: as series! ctx/values/value
	s/offset
]

get-node-facet: func [
	node	[node!]
	facet	[integer!]
	return: [red-value!]
	/local
		ctx	 [red-context!]
		s	 [series!]
][
	ctx: TO_CTX(node)
	s: as series! ctx/values/value
	s/offset + facet
]

get-facets: func [
	msg		[tagMSG]
	return: [red-value!]
][
	get-face-values get-widget-handle msg
]

get-facet: func [
	msg		[tagMSG]
	facet	[integer!]
	return: [red-value!]
][
	get-node-facet 
		as node! GetWindowLong get-widget-handle msg wc-offset + 4
		facet
]

get-widget-handle: func [
	msg		[tagMSG]
	return: [handle!]
	/local
		hWnd   [handle!]
		header [integer!]
		p	   [int-ptr!]
][
	hWnd: msg/hWnd
	header: GetWindowLong hWnd wc-offset

	if header and get-type-mask <> TYPE_OBJECT [
		hWnd: GetParent hWnd							;-- for composed widgets (try 1)
		header: GetWindowLong hWnd wc-offset

		if header and get-type-mask <> TYPE_OBJECT [
			hWnd: WindowFromPoint msg/x msg/y			;-- try 2
			header: GetWindowLong hWnd wc-offset

			if header and get-type-mask <> TYPE_OBJECT [
				p: as int-ptr! GetWindowLong hWnd 0		;-- try 3
				either null? p [
					hWnd: as handle! -1					;-- not found
				][
					hWnd: as handle! p/2
					header: GetWindowLong hWnd wc-offset

					if header and get-type-mask <> TYPE_OBJECT [
						hWnd: as handle! -1				;-- not found
					]
				]
			]
		]
	]
	hWnd
]

get-face-flags: func [
	hWnd	[handle!]
	return: [integer!]
][
	GetWindowLong hWnd wc-offset + 16
]

get-face-handle: func [
	face	[red-object!]
	return: [handle!]
	/local
		state [red-block!]
		int	  [red-integer!]
][
	state: as red-block! get-node-facet face/ctx FACE_OBJ_STATE
	assert TYPE_OF(state) = TYPE_BLOCK
	int: as red-integer! block/rs-head state
	assert TYPE_OF(int) = TYPE_INTEGER
	as handle! int/value
]

get-child-from-xy: func [
	parent	[handle!]
	x		[integer!]
	y		[integer!]
	return: [handle!]
	/local
		hWnd [handle!]
][
	hWnd: RealChildWindowFromPoint parent x y
	either null? hWnd [parent][hWnd]
]


to-bgr: func [
	node	[node!]
	return: [integer!]									;-- 00bbggrr format or -1 if not found
][
	color: as red-tuple! get-node-facet node FACE_OBJ_COLOR
	either TYPE_OF(color) = TYPE_TUPLE [
		color/array1 and 00FFFFFFh
	][
		-1
	]
]

free-handles: func [
	hWnd [handle!]
	/local
		values [red-value!]
		type   [red-word!]
		face   [red-object!]
		tail   [red-object!]
		pane   [red-block!]
		state  [red-value!]
		sym	   [integer!]
		dc	   [integer!]
		cam	   [camera!]
][
	values: get-face-values hWnd
	type: as red-word! values + FACE_OBJ_TYPE
	sym: symbol/resolve type/symbol
	
	case [
		sym = window [
			pane: as red-block! values + FACE_OBJ_PANE
			if TYPE_OF(pane) = TYPE_BLOCK [
				face: as red-object! block/rs-head pane
				tail: as red-object! block/rs-tail pane
				while [face < tail][
					free-handles get-face-handle face
					face: face + 1
				]
			]
		]
		sym = group-box [
			;-- destroy the extra frame window
			DestroyWindow as handle! GetWindowLong hWnd wc-offset - 4 as-integer hWnd
		]
		sym = _image [
			DeleteDC as handle! GetWindowLong hWnd wc-offset - 4
		]
		sym = camera [
			cam: as camera! GetWindowLong hWnd wc-offset - 4
			unless null? cam [
				teardown-graph cam
				free-graph cam
			]
		]
		sym = base [
			dc: GetWindowLong hWnd wc-offset - 4
			unless zero? dc [DeleteDC as handle! dc]			;-- delete cached draw dc
		]
		true [
			0
			;; handle user-provided classes too
		]
	]
	DestroyWindow hWnd
	
	state: values + FACE_OBJ_STATE
	state/header: TYPE_NONE
]

init: func [
	/local
		ver [red-tuple!]
		int [red-integer!]
][
	hScreen: GetDC null
	hInstance: GetModuleHandle 0
	default-font: GetStockObject DEFAULT_GUI_FONT

	version-info/dwOSVersionInfoSize: size? OSVERSIONINFO
	GetVersionEx version-info
	ver: as red-tuple! #get system/view/platform/version

	ver/header: TYPE_TUPLE or (3 << 19)
	ver/array1: version-info/dwMajorVersion
		or (version-info/dwMinorVersion << 8)
		and 0000FFFFh

	register-classes hInstance

	int: as red-integer! #get system/view/platform/build
	int/header: TYPE_INTEGER
	int/value:  version-info/dwBuildNumber

	int: as red-integer! #get system/view/platform/product
	int/header: TYPE_INTEGER
	int/value:  as-integer version-info/wProductType
	
	log-pixels-x: GetDeviceCaps hScreen 88				;-- LOGPIXELSX
	log-pixels-y: GetDeviceCaps hScreen 90				;-- LOGPIXELSY
]

set-logic-state: func [
	hWnd   [handle!]
	state  [red-logic!]
	check? [logic!]
	/local
		value [integer!]
][
	value: either TYPE_OF(state) <> TYPE_LOGIC [
		either check? [BST_INDETERMINATE][false]
	][
		as-integer state/value							;-- returns 0/1, matches the messages
	]
	SendMessage hWnd BM_SETCHECK value 0
]

get-flags: func [
	field	[red-block!]
	return: [integer!]									;-- return a bit-array of all flags
	/local
		word  [red-word!]
		len	  [integer!]
		sym	  [integer!]
		flags [integer!]
][
	switch TYPE_OF(field) [
		TYPE_BLOCK [
			word: as red-word! block/rs-head field
			len: block/rs-length? field
			if zero? len [return 0]
		]
		TYPE_WORD [
			word: as red-word! field
			len: 1
		]
		default [return 0]
	]
	flags: 0
	
	until [
		sym: symbol/resolve word/symbol
		case [
			sym = all-over [flags: flags or FACET_FLAGS_ALL_OVER]
			;; add other flags here
			true [fire [TO_ERROR(script invalid-arg) word]]
		]
		word: word + 1
		len: len - 1
		zero? len
	]
	flags
]

get-logic-state: func [
	msg		[tagMSG]
	return: [logic!]									;-- TRUE if state has changed
	/local
		bool  [red-logic!]
		state [integer!]
		otype [integer!]
		obool [logic!]
][
	bool: as red-logic! get-facet msg FACE_OBJ_DATA
	state: as-integer SendMessage msg/hWnd BM_GETCHECK 0 0

	either state = BST_INDETERMINATE [
		otype: TYPE_OF(bool)
		bool/header: TYPE_NONE							;-- NONE indicates undeterminate
		bool/header <> otype
	][
		obool: bool/value
		bool/value: state = BST_CHECKED
		bool/value <> obool
	]
]

get-selected: func [
	msg [tagMSG]
	idx [integer!]
	/local
		int [red-integer!]
][
	int: as red-integer! get-facet msg FACE_OBJ_SELECTED
	int/value: idx
]

get-text: func [
	msg	[tagMSG]
	idx	[integer!]
	/local
		size	[integer!]
		str		[red-string!]
		out		[c-string!]
][
	size: as-integer either idx = -1 [
		SendMessage msg/hWnd WM_GETTEXTLENGTH idx 0
	][
		SendMessage msg/hWnd CB_GETLBTEXTLEN idx 0
	]
	if size >= 0 [
		str: as red-string! get-facet msg FACE_OBJ_TEXT
		if TYPE_OF(str) <> TYPE_STRING [
			string/make-at as red-value! str size UCS-2
		]
		if size = 0 [
			string/rs-reset str
			exit
		]
		out: unicode/get-cache str size + 1 * 4			;-- account for surrogate pairs and terminal NUL

		either idx = -1 [
			SendMessage msg/hWnd WM_GETTEXT size + 1 as-integer out  ;-- account for NUL
		][
			SendMessage msg/hWnd CB_GETLBTEXT idx as-integer out
		]
		unicode/load-utf16 null size str
	]
]

get-position-value: func [
	pos		[red-float!]
	maximun [integer!]
	return: [integer!]
	/local
		f	[float!]
][
	f: 0.0
	if any [
		TYPE_OF(pos) = TYPE_FLOAT
		TYPE_OF(pos) = TYPE_PERCENT
	][
		f: pos/value * (integer/to-float maximun)
	]
	float/to-integer f
]

get-slider-pos: func [
	msg	[tagMSG]
	/local
		values	[red-value!]
		size	[red-pair!]
		pos		[red-float!]
		int		[integer!]
		divisor [integer!]
][
	values: get-facets msg
	size:	as red-pair!	values + FACE_OBJ_SIZE
	pos:	as red-float!	values + FACE_OBJ_DATA

	if all [
		TYPE_OF(pos) <> TYPE_FLOAT
		TYPE_OF(pos) <> TYPE_PERCENT
	][
		percent/rs-make-at as red-value! pos 0.0
	]
	int: as-integer SendMessage msg/hWnd TBM_GETPOS 0 0
	divisor: size/x
	if size/y > size/x [divisor: size/y int: divisor - int]
	pos/value: (integer/to-float int) / (integer/to-float divisor)
]

get-screen-size: func [
	id		[integer!]									;@@ Not used yet
	return: [red-pair!]
][
	screen-size-x: GetDeviceCaps hScreen HORZRES
	screen-size-y: GetDeviceCaps hScreen VERTRES
	pair/push screen-size-x screen-size-y
]

DWM-enabled?: func [
	return:		[logic!]
	/local
		enabled [integer!]
		dll		[handle!]
		fun		[DwmIsCompositionEnabled!]
][
	enabled: 0
	dll: LoadLibraryEx #u16 "dwmapi.dll" 0 0
	if dll = null [return false]
	fun: as DwmIsCompositionEnabled! GetProcAddress dll "DwmIsCompositionEnabled"
	fun :enabled
	either zero? enabled [false][true]
]

OS-show-window: func [
	hWnd [integer!]
][
	ShowWindow as handle! hWnd SW_SHOWDEFAULT
	UpdateWindow as handle! hWnd
]

OS-make-view: func [
	face	[red-object!]
	parent	[integer!]
	return: [integer!]
	/local
		values	  [red-value!]
		type	  [red-word!]
		str		  [red-string!]
		tail	  [red-string!]
		offset	  [red-pair!]
		size	  [red-pair!]
		data	  [red-block!]
		int		  [red-integer!]
		img		  [red-image!]
		menu	  [red-block!]
		show?	  [red-logic!]
		open?	  [red-logic!]
		selected  [red-integer!]
		para	  [red-object!]
		flags	  [integer!]
		ws-flags  [integer!]
		sym		  [integer!]
		class	  [c-string!]
		caption   [c-string!]
		offx	  [integer!]
		offy	  [integer!]
		value	  [integer!]
		handle	  [handle!]
		hWnd	  [handle!]
		p		  [ext-class!]
		id		  [integer!]
		vertical? [logic!]
		panel?	  [logic!]
][
	values: object/get-values face

	type:	  as red-word!		values + FACE_OBJ_TYPE
	str:	  as red-string!	values + FACE_OBJ_TEXT
	offset:   as red-pair!		values + FACE_OBJ_OFFSET
	size:	  as red-pair!		values + FACE_OBJ_SIZE
	show?:	  as red-logic!		values + FACE_OBJ_VISIBLE?
	open?:	  as red-logic!		values + FACE_OBJ_ENABLE?
	data:	  as red-block!		values + FACE_OBJ_DATA
	img:	  as red-image!		values + FACE_OBJ_IMAGE
	menu:	  as red-block!		values + FACE_OBJ_MENU
	selected: as red-integer!	values + FACE_OBJ_SELECTED
	para:	  as red-object!	values + FACE_OBJ_PARA

	flags: 	  WS_CHILD or WS_CLIPSIBLINGS
	ws-flags: 0
	id:		  0
	sym: 	  symbol/resolve type/symbol
	offx:	  offset/x
	offy:	  offset/y
	panel?:	  no

	if show?/value [flags: flags or WS_VISIBLE]
	if TYPE_OF(para) = TYPE_OBJECT [
		flags: flags or get-para-flags sym para
	]

	if sym = vbase [return -1]

	case [
		sym = button [
			class: #u16 "RedButton"
			;flags: flags or BS_PUSHBUTTON
		]
		sym = check [
			class: #u16 "RedButton"
			flags: flags or WS_TABSTOP or BS_AUTOCHECKBOX
		]
		sym = radio [
			class: #u16 "RedButton"
			flags: flags or WS_TABSTOP or BS_RADIOBUTTON
		]
		any [
			sym = panel 
			sym = group-box
		][
			class: #u16 "RedPanel"
			init-panel values as handle! parent
			offx: offset/x								;-- refresh locals
			offy: offset/y
			panel?: yes
		]
		sym = tab-panel [
			class: #u16 "RedTabPanel"
		]
		sym = field [
			class: #u16 "RedField"
			flags: flags or ES_LEFT or ES_AUTOHSCROLL
			ws-flags: WS_TABSTOP or WS_EX_CLIENTEDGE
		]
		sym = area [
			class: #u16 "RedField"
			flags: flags or ES_LEFT or ES_AUTOVSCROLL or ES_AUTOHSCROLL or ES_MULTILINE
			ws-flags: WS_TABSTOP or WS_EX_CLIENTEDGE
		]
		sym = text [
			class: #u16 "RedFace"
			flags: flags or SS_SIMPLE
		]
		sym = text-list [
			class: #u16 "RedListBox"
			flags: flags or LBS_NOTIFY or WS_HSCROLL or WS_VSCROLL
		]
		sym = drop-down [
			class: #u16 "RedCombo"
			flags: flags or CBS_DROPDOWN or CBS_HASSTRINGS ;or WS_OVERLAPPED
		]
		sym = drop-list [
			class: #u16 "RedCombo"
			flags: flags or CBS_DROPDOWNLIST or CBS_HASSTRINGS ;or WS_OVERLAPPED
		]
		sym = progress [
			class: #u16 "RedProgress"
			if size/y > size/x [flags: flags or PBS_VERTICAL]
		]
		sym = slider [
			class: #u16 "RedSlider"
			if size/y > size/x [
				flags: flags or TBS_VERT or TBS_DOWNISLEFT
			]
		]
		sym = _image [
			class: #u16 "RedImage"
		]
		sym = camera [
			class: #u16 "RedCamera"
		]
		sym = base [
			class: #u16 "Base"
		]
		sym = window [
			class: #u16 "RedWindow"
			flags: WS_OVERLAPPEDWINDOW ;or WS_CLIPCHILDREN
			offx:  CW_USEDEFAULT
			offy:  CW_USEDEFAULT
			if menu-bar? menu window [
				id: as-integer build-menu menu CreateMenu
			]
		]
		true [											;-- search in user-defined classes
			p: find-class type
			class: p/class
			ws-flags: ws-flags or p/ex-styles
			flags: flags or p/styles
			id: p/base-id
		]
	]

	caption: either TYPE_OF(str) = TYPE_STRING [
		unicode/to-utf16 str
	][
		null
	]

	unless DWM-enabled? [
		ws-flags: ws-flags or WS_EX_COMPOSITED			;-- this flag conflicts with DWM
	]

	handle: CreateWindowEx
		ws-flags
		class
		caption
		flags
		offx
		offy
		size/x
		size/y
		as int-ptr! parent
		as handle! id
		hInstance
		null

	if null? handle [print-line "*** Error: CreateWindowEx failed!"]

	BringWindowToTop handle
	set-font handle face values

	;-- extra initialization
	case [
		sym = button	[init-button handle values]
		sym = camera	[init-camera handle data open?/value]
		sym = text-list [init-text-list handle data selected]
		sym = _image	[init-image handle data img]
		sym = tab-panel [set-tabs handle values]
		sym = group-box [
			flags: flags or WS_GROUP or BS_GROUPBOX
			hWnd: CreateWindowEx
				ws-flags
				#u16 "BUTTON"
				caption
				flags
				0
				0
				size/x
				size/y
				handle
				null
				hInstance
				null

			SendMessage hWnd WM_SETFONT as-integer default-font 1
			SetWindowLong handle wc-offset - 4 as-integer hWnd
		]
		panel? [
			adjust-parent handle as handle! parent offx offy
		]
		sym = slider [
			vertical?: size/y > size/x
			value: either vertical? [size/y][size/x]
			SendMessage handle TBM_SETRANGE 1 value << 16
			value: get-position-value as red-float! data value
			if vertical? [value: size/y - value]
			SendMessage handle TBM_SETPOS 1 value
		]
		sym = progress [
			value: get-position-value as red-float! data 100
			SendMessage handle PBM_SETPOS value 0
		]
		sym = check [set-logic-state handle as red-logic! data yes]
		sym = radio [set-logic-state handle as red-logic! data no]
		any [
			sym = drop-down
			sym = drop-list
		][
			init-drop-list handle data caption selected sym = drop-list
		]
		sym = base [SetWindowLong handle wc-offset - 4 0]
		true [0]
	]
	
	;-- store the face value in the extra space of the window struct
	assert TYPE_OF(face) = TYPE_OBJECT					;-- detect corruptions caused by CreateWindow unwanted events
	SetWindowLong handle wc-offset		  		   face/header
	SetWindowLong handle wc-offset + 4  as-integer face/ctx
	SetWindowLong handle wc-offset + 8  		   face/class
	SetWindowLong handle wc-offset + 12 as-integer face/on-set
	SetWindowLong handle wc-offset + 16 get-flags as red-block! values + FACE_OBJ_FLAGS

	as-integer handle
]

change-size: func [
	hWnd [integer!]
	size [red-pair!]
][
	SetWindowPos 
		as handle! hWnd
		as handle! 0
		0 0
		size/x size/y 
		SWP_NOMOVE or SWP_NOZORDER
]

change-offset: func [
	hWnd [integer!]
	pos  [red-pair!]
][
	SetWindowPos 
		as handle! hWnd
		as handle! 0
		pos/x pos/y
		0 0
		SWP_NOSIZE or SWP_NOZORDER
]

change-text: func [
	hWnd [integer!]
	str  [red-string!]
	type [red-word!]
	/local
		text [c-string!]
][
	text: null
	switch TYPE_OF(str) [
		TYPE_STRING [text: unicode/to-utf16 str]
		TYPE_NONE	[text: #u16 "^@"]
		default		[0]									;@@ Auto-convert?
	]
	unless null? text [
		if type/symbol = group-box [
			hWnd: GetWindowLong as handle! hWnd wc-offset - 4
		]
		SetWindowText as handle! hWnd text
	]
]

change-visible: func [
	hWnd  [integer!]
	show? [logic!]
	type  [red-word!]
	/local
		value [integer!]
][
	value: either show? [SW_SHOW][SW_HIDE]
	ShowWindow as handle! hWnd value
	if type/symbol = group-box [
		hWnd: GetWindowLong as handle! hWnd wc-offset - 4
		ShowWindow as handle! hWnd value
	]
]

change-enable: func [
	hWnd	[integer!]
	enable? [logic!]
][
	toggle-preview as handle! hWnd enable?
]

change-selection: func [
	hWnd   [integer!]
	idx	   [integer!]
	values [red-value!]
	/local
		type [red-word!]
		sym	 [integer!]
][
	type: as red-word! values + FACE_OBJ_TYPE
	sym: symbol/resolve type/symbol
	case [
		sym = camera [
			select-camera as handle! hWnd idx - 1
		]
		sym = text-list [
			SendMessage as handle! hWnd LB_SETCURSEL idx - 1 0
		]
		any [sym = drop-list sym = drop-down][
			SendMessage as handle! hWnd CB_SETCURSEL idx - 1 0
		]
		sym = tab-panel [
			select-tab as handle! hWnd idx - 1
		]
	]
]

change-data: func [
	hWnd   [handle!]
	values [red-value!]
	/local
		data 	[red-value!]
		word 	[red-word!]
		f		[red-float!]
		str		[red-string!]
		caption [c-string!]
		type	[integer!]
][
	data: as red-value! values + FACE_OBJ_DATA
	word: as red-word! values + FACE_OBJ_TYPE
	type: word/symbol
	
	case [
		all [
			type = progress
			TYPE_OF(data) = TYPE_PERCENT
		][
			f: as red-float! data
			SendMessage hWnd PBM_SETPOS float/to-integer f/value * 100.0 0
		]
		type = check [
			set-logic-state hWnd as red-logic! data yes
		]
		type = radio [
			set-logic-state hWnd as red-logic! data no
		]
		type = _image [
			init-image hWnd as red-block! data as red-image! values + FACE_OBJ_IMAGE
			InvalidateRect hWnd null 1
		]
		type = tab-panel [
			set-tabs hWnd get-face-values hWnd
		]
		any [type = drop-list type = drop-down][
			str: as red-string! values + FACE_OBJ_TEXT
			caption: either TYPE_OF(str) = TYPE_STRING [
				unicode/to-utf16 str
			][
				null
			]
			init-drop-list 
				hWnd
				as red-block! data
				caption
				as red-integer! values + FACE_OBJ_SELECTED
				type = drop-list
		]
		true [0]										;-- default, do nothing
	]
]

change-faces-parent: func [
	pane   [red-block!]
	parent [red-object!]
	new	   [red-value!]
	index  [integer!]
	part   [integer!]
	/local
		face [red-object!]
		tail [red-object!]
][
	assert TYPE_OF(pane) = TYPE_BLOCK
	face: as red-object! either null? new [block/rs-abs-at pane index][new]
	tail: face + part
	assert tail <= as red-object! block/rs-tail pane
	
	while [face < tail][
		if TYPE_OF(face) = TYPE_OBJECT [change-parent face parent]
		face: face + 1
	]
]

change-parent: func [
	face   [red-object!]
	parent [red-object!]
	/local
		hWnd		[handle!]
		bool		[red-logic!]
		type		[red-word!]
		values		[red-value!]
		offset		[red-pair!]
		tab-panel?	[logic!]
][
	hWnd: get-face-handle face
	values: get-node-facet face/ctx 0
	bool: as red-logic! values + FACE_OBJ_VISIBLE?
	tab-panel?: no
	
	if parent <> null [
		assert TYPE_OF(parent) = TYPE_OBJECT
		type: as red-word! get-node-facet parent/ctx FACE_OBJ_TYPE
		tab-panel?: tab-panel = symbol/resolve type/symbol
	]
	unless tab-panel? [bool/value: parent <> null]
	
	either null? parent [
		change-visible as-integer hWnd no as red-word! values + FACE_OBJ_TYPE
		SetParent hWnd null
	][
		if tab-panel? [exit]
		SetParent hWnd get-face-handle parent
	]
	OS-show-window as-integer hWnd
]

update-z-order: func [
	pane [red-block!]
	hdwp [handle!]
	/local
		face [red-object!]
		tail [red-object!]
		type [red-word!]
		blk	 [red-block!]
		s	 [series!]
		nb	 [integer!]
		sub? [logic!]
][
	s: GET_BUFFER(pane)
	
	face: as red-object! s/offset + pane/head
	tail: as red-object! s/tail
	nb: (as-integer tail - face) >> 4
	
	sub?: either null? hdwp [
		hdwp: BeginDeferWindowPos nb
		no
	][
		yes
	]

	while [face < tail][
		if TYPE_OF(face) = TYPE_OBJECT [
			hdwp: DeferWindowPos
				hdwp
				get-face-handle face
				as handle! 0							;-- HWND_TOP
				0 0
				0 0
				SWP_NOSIZE or SWP_NOMOVE
			
			type: as red-word! get-node-facet face/ctx FACE_OBJ_TYPE
			
			if tab-panel = symbol/resolve type/symbol [
				;-- ensures that panels are above the tab-panel
				blk: as red-block! get-node-facet face/ctx FACE_OBJ_PANE
				if TYPE_OF(blk) = TYPE_BLOCK [update-z-order blk hdwp]
			]
		]
		face: face + 1
	]
	unless sub? [EndDeferWindowPos hdwp]
]

unlink-sub-obj: func [
	face  [red-object!]
	obj   [red-object!]
	field [integer!]
	/local
		values [red-value!]
		parent [red-block!]
		res	   [red-value!]
][
	values: object/get-values obj
	parent: as red-block! values + field
	
	if TYPE_OF(parent) = TYPE_BLOCK [
		res: block/find parent as red-value! face null no no no null null no no no no
		if TYPE_OF(res) <> TYPE_NONE [_series/remove as red-series! res null]
		if all [
			field = FONT_OBJ_PARENT
			block/rs-tail? parent
		][
			free-font obj
		]
	]
]

OS-update-view: func [
	face [red-object!]
	/local
		ctx		[red-context!]
		values	[red-value!]
		state	[red-block!]
		menu	[red-block!]
		draw	[red-block!]
		word	[red-word!]
		int		[red-integer!]
		int2	[red-integer!]
		bool	[red-logic!]
		s		[series!]
		hWnd	[integer!]
		flags	[integer!]
][
	ctx: GET_CTX(face)
	s: as series! ctx/values/value
	values: s/offset

	state: as red-block! values + FACE_OBJ_STATE
	s: GET_BUFFER(state)
	int: as red-integer! s/offset
	hWnd: int/value
	int: int + 1
	flags: int/value

	if flags and FACET_FLAG_OFFSET <> 0 [
		change-offset hWnd as red-pair! values + FACE_OBJ_OFFSET
	]
	if flags and FACET_FLAG_SIZE <> 0 [
		change-size hWnd as red-pair! values + FACE_OBJ_SIZE
	]
	if flags and FACET_FLAG_TEXT <> 0 [
		change-text
			hWnd
			as red-string! values + FACE_OBJ_TEXT
			as red-word! values + FACE_OBJ_TYPE
	]
	if flags and FACET_FLAG_DATA <> 0 [
		change-data	as handle! hWnd values
	]
	if flags and FACET_FLAG_ENABLE? <> 0 [
		bool: as red-logic! values + FACE_OBJ_ENABLE?
		change-enable hWnd bool/value
	]
	if flags and FACET_FLAG_VISIBLE? <> 0 [
		bool: as red-logic! values + FACE_OBJ_VISIBLE?
		change-visible hWnd bool/value as red-word! values + FACE_OBJ_TYPE
	]
	if flags and FACET_FLAG_SELECTED <> 0 [
		int2: as red-integer! values + FACE_OBJ_SELECTED
		change-selection hWnd int2/value values
	]
	if flags and FACET_FLAG_FLAGS <> 0 [
		SetWindowLong as handle! hWnd wc-offset + 16 get-flags as red-block! values + FACE_OBJ_FLAGS
	]
	if flags and FACET_FLAG_DRAW  <> 0 [
		SetWindowLong as handle! hWnd wc-offset - 4 0
		InvalidateRect as handle! hWnd null 1
	]
	if flags and FACET_FLAG_COLOR <> 0 [
		InvalidateRect as handle! hWnd null 1
	]
	if flags and FACET_FLAG_PANE <> 0 [
		word: as red-word! values + FACE_OBJ_TYPE
		if tab-panel <> symbol/resolve word/symbol [	;-- tab-panel/pane has custom z-order handling
			update-z-order 
				as red-block! values + gui/FACE_OBJ_PANE
				null
		]
	]
	if flags and FACET_FLAG_FONT <> 0 [
		set-font as handle! hWnd face values
		InvalidateRect as handle! hWnd null 1
	]
	if flags and FACET_FLAG_PARA <> 0 [
		InvalidateRect as handle! hWnd null 1
	]
	if flags and FACET_FLAG_MENU <> 0 [
		menu: as red-block! values + FACE_OBJ_MENU
		if menu-bar? menu window [
			DestroyMenu GetMenu as handle! hWnd
			SetMenu as handle! hWnd build-menu menu CreateMenu
		]
	]
	
	int/value: 0										;-- reset flags
]

OS-destroy-view: func [
	face   [red-object!]
	empty? [logic!]
	/local
		values [red-value!]
		obj	   [red-object!]
][
	free-handles get-face-handle face
	values: object/get-values face
	
	obj: as red-object! values + FACE_OBJ_FONT
	if TYPE_OF(obj) = TYPE_OBJECT [unlink-sub-obj face obj FONT_OBJ_PARENT]
	
	obj: as red-object! values + FACE_OBJ_PARA
	if TYPE_OF(obj) = TYPE_OBJECT [unlink-sub-obj face obj PARA_OBJ_PARENT]
	
	if empty? [clean-up PostQuitMessage 0]
]

OS-update-facet: func [
	face   [red-object!]
	facet  [red-word!]
	value  [red-value!]
	action [red-word!]
	new	   [red-value!]
	index  [integer!]
	part   [integer!]
	/local
		word [red-word!]
		sym	 [integer!]
		type [integer!]
		hWnd [handle!]
][
	sym: symbol/resolve facet/symbol
	
	case [
		sym = facets/pane [
			sym: action/symbol 
			case [
				any [
					sym = words/_remove/symbol
					sym = words/_take/symbol
					sym = words/_clear/symbol
				][
					change-faces-parent as red-block! value null new index part
				]
				any [
					sym = words/_insert/symbol
					sym = words/_poke/symbol			;@@ unbind old value
					sym = words/_put/symbol				;@@ unbind old value
				][
					change-faces-parent as red-block! value face new index part
				]
				true [0]
			]
		]
		sym = facets/data [
			word: as red-word! get-node-facet face/ctx FACE_OBJ_TYPE
			type: symbol/resolve word/symbol
			sym: action/symbol
			case [
				type = text-list [
					update-list face value sym new index part no
				]
				any [
					type = drop-list
					type = drop-down
				][
					if any [
						index and 1 = 1
						part  and 1 = 1
					][
						fire [TO_ERROR(script invalid-data-facet) value]
					]
					index: index / 2
					part:   part / 2
					if zero? part [exit]
					
					update-list face value sym new index part yes
				]
				type = tab-panel [
					update-tabs	face value sym new index part
				]
				true [OS-update-view face]
			]
		]
		true [OS-update-view face]
	]
]

OS-to-image: func [
	face	[red-object!]
	return: [red-image!]
	/local
		hWnd 	[handle!]
		dc		[handle!]
		mdc		[handle!]
		rect	[RECT_STRUCT]
		width	[integer!]
		height	[integer!]
		bmp		[handle!]
		bitmap	[integer!]
		img		[red-image!]
		word	[red-word!]
		type	[integer!]
		size	[red-pair!]
		screen? [logic!]
][
	rect: declare RECT_STRUCT
	word: as red-word! get-node-facet face/ctx FACE_OBJ_TYPE
	screen?: screen = symbol/resolve word/symbol
	either screen? [
		size: as red-pair! get-node-facet face/ctx FACE_OBJ_SIZE
		width: size/x
		height: size/y
		rect/left: 0
		rect/top: 0
		dc: hScreen
	][
		hWnd: get-face-handle face
		GetWindowRect hWnd rect
		width: rect/right - rect/left
		height: rect/bottom - rect/top
		dc: GetDC hWnd
	]

	mdc: CreateCompatibleDC dc
	bmp: CreateCompatibleBitmap dc width height
	SelectObject mdc bmp
	BitBlt mdc 0 0 width height hScreen rect/left rect/top SRCCOPY

	bitmap: 0
	GdipCreateBitmapFromHBITMAP bmp 0 :bitmap

	either zero? bitmap [img: as red-image! none-value][
		img: image/init-image as red-image! stack/push* bitmap
	]

    DeleteDC mdc
    DeleteObject bmp
    unless screen? [ReleaseDC hWnd dc]
	img
]

OS-do-draw: func [
	img		[red-image!]
	cmds	[red-block!]
][
	do-draw null img cmds no no
]
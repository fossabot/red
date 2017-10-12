Red [
	Title:	 "Red GUI Console"
	Author:	 "Qingtian Xie"
	File:	 %red-console.red
	Tabs:	 4
	Icon:	 %app.ico
	Version: 0.0.1
	Needs:	 View
	Config:	 [gui-console?: yes red-help?: yes]
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

debug-print: routine [arg [any-type!] /local blk [red-block!]][
	"Output debug info to CLI console only"
	#if sub-system = 'console [
		if TYPE_OF(arg) = TYPE_BLOCK [
			block/rs-clear natives/buffer-blk
			stack/push as red-value! natives/buffer-blk
			natives/reduce* no 1
			blk: as red-block! arg
			blk/head: 0						;-- head changed by reduce/into
		]
		actions/form* -1
		dyn-print/red-print-cli as red-string! stack/arguments yes
	]
]

#include %../console/help.red
#include %../console/engine.red
#include %../console/auto-complete.red
#include %highlight.red
#include %tips.red

gui-console-ctx: context [
	cfg-path:	none
	cfg:		none
	font:		make font! [name: "Consolas" size: 11 color: 0.0.0]
	scroller:	make scroller! []

	console:	make face! [
		type: 'base color: 0.0.128 offset: 0x0 size: 400x400
		flags:   [Direct2D editable scrollable all-over]
		options: [cursor: I-beam]
		menu: [
			"Copy^-Ctrl+C"		 copy
			"Paste^-Ctrl+V"		 paste
			"Select All^-Ctrl+A" select-all
		]
		actors: object [
			on-time: func [face [object!] event [event!]][
				caret/rate: 2
				face/rate: none
			]
			on-drawing: func [face [object!] event [event!]][
				terminal/paint
			]
			on-scroll: func [face [object!] event [event!]][
				terminal/scroll event
			]
			on-wheel: func [face [object!] event [event!]][
				terminal/scroll event
			]
			on-key: func [face [object!] event [event!]][
				terminal/press-key event
			]
			on-ime: func [face [object!] event [event!]][
				terminal/process-ime-input event
			]
			on-down: func [face [object!] event [event!]][
				terminal/mouse-down event
			]
			on-up: func [face [object!] event [event!]][
				terminal/mouse-up event
			]
			on-over: func [face [object!] event [event!]][
				terminal/mouse-move event
			]
			on-menu: func [face [object!] event [event!]][
				switch event/picked [
					copy		[terminal/copy-selection]
					paste		[terminal/paste]
					select-all	['TBD]
				]
			]
		]

		init: func [/local box][
			box: terminal/box
			box/fixed?: yes
			box/styles: make block! 200
			scroller: get-scroller self 'horizontal
			scroller/visible?: no						;-- hide horizontal bar
			scroller: get-scroller self 'vertical
			scroller/position: 1
			scroller/max-size: 2
		]
	]

	caret:		make face! [
		type: 'base color: 0.0.0.1 offset: 0x0 size: 1x17 rate: 2
		options: compose [caret (console) cursor: I-beam]
		actors: object [
			on-time: func [face [object!] event [event!]][
				face/color: either face/color = 0.0.0.1 [255.255.255.254][0.0.0.1]
			]
		]
	]
	tips:		make tips! [visible?: no]

	terminal:	#include %core.red

	#include %settings.red

	setup-faces: does [
		append win/pane reduce [console tips caret]
		win/menu: [
			"File" [
				"Open..."			open-file
				---
				"Quit"				quit
			]
			"Options" [
				"Choose Font..."	choose-font
				;"Settings..."		settings
			]
			"Plugins" [
				"Add..."			add-plugin
			]
			"Help" [
				"About"				about-msg
			]
		]
		win/actors: object [
			on-menu: func [face [object!] event [event!] /local ft][
				switch event/picked [
					about-msg		[display-about]
					quit			[self/on-close face event]
					choose-font		[
						if ft: request-font/font/mono font [
							font: ft
							console/font: font
							terminal/update-cfg font cfg
						]
					]
					settings		[show-cfg-dialog]
				]
			]
			on-close: func [face [object!] event [event!]][
				save-cfg
				clear head system/view/screens/1/pane
			]
			on-resizing: function [face [object!] event [event!]][
				new-sz: face/size
				console/size: new-sz
				terminal/resize new-sz
				system/console/size: new-sz
				unless system/view/auto-sync? [show face]
			]
		]
		tips/parent: win
	]

	win: layout/tight [						;-- main window
		title "Red Console"
		size  640x480
	]

	launch: func [/local svs][
		setup-faces
		win/visible?: no					;-- hide it first to avoid flicker

		view/flags/no-wait win [resize]		;-- create window instance
		console/init
		load-cfg
		win/visible?: yes

		svs: system/view/screens/1
		svs/pane: next svs/pane				;-- proctect itself from unview/all

		system/console/launch
	]
]

ask: function [
	question [string!]
	return:  [string!]
][
	unless gui-console-ctx/console/state [
		return "quit"
	]
	line: make string! 8
	line: insert line question
	
	vt: gui-console-ctx/terminal
	vt/line: line
	vt/pos: 0
	vt/add-line line
	vt/ask?: yes
	vt/reset-top/force
	system/view/platform/redraw gui-console-ctx/console
	either vt/paste/resume [
		do-events/no-wait
	][
		do-events
	]
	vt/ask?: no
	line
]

#system [
	red-print-gui: func [
		str		[red-string!]
		lf?		[logic!]
	][
		#call [gui-console-ctx/terminal/vprint str lf?]
	]

	rs-print-gui: func [
		cstr	[c-string!]
		size	[integer!]
		lf?		[logic!]
		/local
			str [red-string!]
	][
		str: declare red-string!
		if negative? size [size: length? cstr]
		either TYPE_OF(str) = TYPE_STRING [
			string/rs-reset str
			unicode/load-utf8-buffer cstr size GET_BUFFER(str) null yes
		][
			str/header: TYPE_STRING
			str/head: 0
			str/node: unicode/load-utf8-buffer cstr size null null yes
			str/cache: null
		]
		red-print-gui str lf?
	]

	dyn-print/add as int-ptr! :red-print-gui null ;as int-ptr! :rs-print-gui
]

gui-console-ctx/launch
Red [
	Title:		"Red GUI Console"
	File:		%gui-console.red
	Tabs:		4
	Icon:		default
	Version:	0.9.0
	Needs:		View
	Config:		[
		gui-console?: yes
		red-help?: yes
	]
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/red/red/blob/master/BSL-License.txt
	}
]

#include %help.red
#include %engine.red
#include %auto-complete.red

#system [
	#include %terminal.reds
]

#include %../../../red-scintilla/src/scintilla/api.red
#include %../../../red-scintilla/src/call/call.red
#include %../../../red-scintilla/src/tools.red
#include %../../../red-scintilla/src/editor.red


ask: routine [
	question [string!]
	return:  [string!]
][
	as red-string! _series/copy
		as red-series! terminal/ask question
		as red-series! stack/arguments
		null
		yes
		null
]

input: does [ask ""]

gui-console-ctx: context [
	copy-text:   routine [face [object!]][terminal/copy-text   face]
	paste-text:  routine [face [object!]][terminal/paste-text  face]
	select-text: routine [face [object!]][terminal/select-text face]

	font-name: pick ["Fixedsys" "Consolas"] make logic! find [5.1.0 5.0.0] system/view/platform/version

	console: make face! [
		type: 'console size: 640x400
		font: make font! [name: font-name size: 11]
		menu: [
			"Copy^-Ctrl+C"		 copy
			"Paste^-Ctrl+V"		 paste
			"Select All^-Ctrl+A" select-all
		]
		actors: object [
			on-menu: func [face [object!] event [event!]][
				switch event/picked [
					copy		[copy-text   face]
					paste		[paste-text  face]
					select-all	[select-text face]
				]
			]
		]
	]

	win: make face! [
		type: 'window text: "Red Console" size: 640x400 selected: console
		actors: object [
			on-close: func [face [object!] event [event!]][
				unview/all
			]
			on-resizing: func [face [object!] event [event!]][
				console/size: event/offset
				unless system/view/auto-sync? [show face]
			]
		]
		pane: reduce [console]
	]
	
	launch: does [
		view/flags/no-wait win [resize]
		svs: system/view/screens/1
		svs/pane: next svs/pane

		system/console/launch
		do-events
	]
]

gui-console-ctx/launch


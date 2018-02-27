// Shackle System version 2

// OSC message protocol
// --- sending ---
// while counting down next action:
//			"/nextaction", 0 - 3 (cancel, change, continue, develop)
//			"/countaction", countdown for action accept
//			"/transition", 0 - 1 (hardcut, crossfade)
// when action is not cancelled, send the new action:
//			"/action", 0 - 3 (cancel, change, continue, develop)
// when action is cancelled, send the old action:
//			"/action", 0 - 3 (cancel, change, continue, develop)
// and send transition count
//			"/counttransition", count for transition time
// --- receiving ---
// cancel nextaction or request new action:
// 			"/cancelnext"

(
/////////////////////////////////////////////  variables //////////////////////////////////////

var
testMode = false, 			// if true the OSC is send to localhost
remote = NetAddrMon("169.254.0.1", 57121), // to Anne
local = NetAddrMon("127.0.0.1", 57120), // to localhost for SC
client1 = if(testMode, { local }, { remote }),

timeFactor = 1,			// multiplication factor for wait times, countdowns
currentActionID = 2,		// holds the current action
nextActionID = 2,			// holds the next, proposed action
actionIDs = [1, 2, 3],	// possible action ids
actionNames = [\cancel, \switch, \stay, \develop],		// corresponding action names, with cancel being 0
actionNamesAlt = [\cancel, \switched, \staying, \developing],		// corresponding action names, with cancel being 0
actionChooserNames = actionNames.select({|item,index| index > 0}),	// action names for dropdown
waitMin = 3 * 60,				// lower boundary for random choice wait time
waitMax = 4 * 60,				// upper boundary for random choice wait time
transitions = [ ["hardcut", "|", 5, 10], ["crossfade", "X", 10, 30] ],
									// array with for each transition: name, symbol, lower and upper time boundary
logFile = Document.dir++"Shackle/Data/ShackleSystem/log_v2.txt",

onLine = 1,									// whether to show the button to switch online
showClock = 0,							// whether to show clock or not
winAdd = 0, 									// add to width & height of the window, centering the contents
showCount = 0,							// show counting seconds in post window
countdownDefault = (15 * timeFactor).round(1),		// the number of countdown seconds
countdown = countdownDefault,
cancelFactor = 2,  						// the factor the wait times are divided by after cancelling
remoteClientsOnline = 0,				// when 0 no OSC msg will be send to clients below which are not local
textCancel = "<cancelled>",   		// value displayed when cancel received
textNext = "<next>",   					// value displayed when next part is requested
receivingCancel = "/cancel",  		// cancel value received from other player
receivingNext = "/next",  				// next part value received from other player
enableRemoteCancelNext = 1
;

var fMessaging, fSendMsg, fNewClock, tNewClock, fOscResponder, lapisStat;
var transitionClock = TempoClock(), transitionTask, transitionTime = 0;
var waitTime, actionsClock = TempoClock(), tGenerateAuto, tActionGenerator;
var countUp = 0, cancelAction = 0, cancelActionClock = TempoClock(), nextAction = 0, nextActionClock = TempoClock();
var transitionNbr = 0, firstCountdown = 1, tick = 0, counting = 0;
var wActionGenerator, signalColor = Color.green(0.9), screenHeight = Window.screenBounds.height;
var displayCurrentAction, displayNextAction, displayClock, displayTransition, transitionFader, actionChooser;
var fileSaveLog, rect = (), font = (), bRun, bCancelNext, bOSCin, bOSCout, bRemoteClientsOnline;

// global var to use in SynthDef for sending BPM
~shackleRemoteClientsOnline = remoteClientsOnline;

// OSC listening port
("\nSC is listening to OSC on port:" + NetAddr.langPort).postln;

// (Document.dir++"Lapis/GlobalVars.scd").load();

///////////////////////////////////////////// functions //////////////////////////////////////

// sending OSC to a NetAddr
fSendMsg = {
	arg netaddr, label, value;
	if( (remoteClientsOnline == 1) || (netaddr.ip == "127.0.0.1"), {
		try
		{ netaddr.sendMsg(label, value) }
		{ ("\nNetAddr Error with"+label+value).postln; }
	});
};

// send OSC and update GUI
fMessaging =
{
	arg mode, actionID = "", count, transition = "", alwaysSend = true;
	var actionName, transitionName, transitionSymbol;

	if(actionID != "", {actionName = actionNames[actionID].asString});
	// [mode, actionID, actionName, count].postln;
	if((transition != ""),{
		transitionName = transitions[transition][0];
		transitionSymbol = transitions[transition][1];
	});

	case
	{mode == "transition"} // transition count
	{
		fSendMsg.value(client1, "/counttransition", count);
	}
	{mode == "next"}
	{
		// remote
		fSendMsg.value(client1, "/countaction", count);
		if(alwaysSend, { // only send to client1 (=Anne) when this flag=1
			fSendMsg.value(client1, "/nextaction",actionID);
			fSendMsg.value(client1, "/transition",transition);
		});
		// local
		displayNextAction.states_([[actionName ++ "(" ++ count ++ ")", Color.black, signalColor]]).font_(font.nextAction);
		displayTransition.string = transitionSymbol;
	}
	{mode == "lastnext"} // last time next action is displayed, this time without count
	{
		// remote
		fSendMsg.value(client1, "/countaction", 0);
		// local
		displayNextAction.states_([[actionName]]);
	}
	{mode == "new"} // decided action, after countdown
	{
		// remote
		fSendMsg.value(client1, "/action", actionID);
		{ // send again just to be sure it arrives
			fSendMsg.value(client1, "/action", actionID);
		}.defer(0.5);
		// local
		displayTransition.string = transitionSymbol;
	}
	{mode == "action"} // cancel or next action
	{
		// remote
		fSendMsg.value(client1, "/nextaction", actionID);
		// local
		if(actionID == 0,
			{ displayNextAction.states = [[textCancel]] },
			{ displayNextAction.states = [[textNext]] });
		displayNextAction.font_(font.nextAction);
	}
	{mode == "clear"} // clear fields
	{
		// local
		displayNextAction.states = [[""]];
		displayTransition.string = "";
	}
	{mode == "start"} // when starting (1) and stopping (0) the generator
	{
		// remote
		fSendMsg.value(client1, "/start", actionID);
		// local
		displayCurrentAction.states = [[""]];
	}
	;
};

// starting and stopping of OSC responders
fOscResponder = {
	// responder to receive the cancel/next part msg from the other player
	OSCdef(\shackSysCancelNext, { arg message;
		("\nOSC RCV: " ++ message).postln;
		if(enableRemoteCancelNext==1, {
			// if counting up in task, cancel part
			if(countUp != 0, { { bCancelNext.valueAction = 1 }.defer(0.2) });
			// if not counting up in task, call next part
			if(countUp == 0, { { bCancelNext.valueAction = 0 }.defer(0.2) });
		});
	}, receivingCancel).fix;
};

fNewClock = {
	tick = 0;
	inf.do({
		1.wait;
		if( (tick%60) == 0, { ("\n### "  + (tick/60) + "minutes and counting #######").postln });
		tick = tick + 1;
		// { displayClock.string = if(tick>=3600, "  ","   ")++tick.asTimeString }.defer();
		{displayClock.states = [[tick.asTimeStringHM]]}.defer();
	});
};

///////////////////////////////////////////// tasks //////////////////////////////////////

tActionGenerator = Task({
	inf.do {
		// choose part number
		nextActionID = actionIDs.choose;
		while(
			// if chosen action is the same and it is NOT \change, choose another
			{ (nextActionID == currentActionID) && (currentActionID != 1)},
			{nextActionID = actionIDs.choose}
		);

		// get action name
		("\nProposed action:" + actionNames[nextActionID] + "(" ++ nextActionID ++ ")").postln;

		// choose transition
		transitionNbr = transitions.size.rand;
		("Proposed transition:" + transitions[transitionNbr][0] + "(" ++ transitionNbr ++ ")").postln;

		// announce new action
		while(
			{ countUp < countdown && cancelAction == 0 }, // jump out if we're cancelling
			{   // this is used for this while loop and to indicate we're counting down
				countUp = countUp + 1;

				// send OSC out & display next
				{ fMessaging.value(
					"next",
					nextActionID,
					(countdown - countUp + 1),
					transitionNbr,
					countUp <= 5 // send next action and transition only on the first 5 counts
				) }.defer();

				// only if we're not cancelling to make sure we don't whipe out <cancelled>
				if(cancelAction == 0, { 0.5.wait });
				if(cancelAction == 0, { { fMessaging.value("clear") }.defer() });
				if(cancelAction == 0, { 0.5.wait} );
				if((cancelAction == 0) && (countUp == countdown), { { fMessaging.value("lastnext", nextActionID) }.defer() });
		});
		countUp = 0;

		// set button to 'NEXT'
		{ bCancelNext.value = 1 }.defer(0.2);

		if((cancelAction == 0), { // no cancel
			// store new action
			currentActionID = nextActionID;
			("\nAccepted action:" + currentActionID + actionNames[currentActionID]).postln;

			// keep track of first cancel
			if(firstCountdown == 1, { firstCountdown = 0; "\nGenerator: just finished first countdown".postln });

			// send out OSC about new action and display locally
			{ fMessaging.value("new", currentActionID, "", transitionNbr) }.defer();
		}, {
			// if cancelling restore original action
			("\nPrevious action after cancel:" + actionNames[currentActionID] + "(" ++ currentActionID ++ ")").postln;

			// log cancellation
			fileSaveLog.write(Date.getDate.asString + "<cancelled>\n");

			// if cancelled and first countdown, force next
			if(firstCountdown == 1, { { bCancelNext.valueAction_(0) }.defer() });
		});

		// determine random wait
		waitTime = (rrand(waitMin, waitMax)* timeFactor).round(1) ;
		// if cancelled and not the first cancel, divide length by factor
		if( (cancelAction != 0) && (firstCountdown == 0 ),{
			("\nWait time before cancel factor:" + waitTime + "sec").postln;
			waitTime = (waitTime / cancelFactor).round(1);
		}, {"".postln});
		("Wait time:" + waitTime + "sec").postln;

		// start transition count
		if(cancelAction == 0, {
			transitionTime = rrand(transitions[transitionNbr][2], transitions[transitionNbr][3]);
			// transition time is always less than 80% of wait time
			transitionTime = (min(transitionTime, 0.8 * waitTime) * timeFactor).round(1);
			("Transition time:" + transitionTime + "sec").postln;
			transitionTask.start;
		});

		// log choice
		fileSaveLog.write(Date.getDate.asString +
			if(showClock == 1, { "TICK" + tick.asTimeStringHM ++ " " }, {""}) ++
			"Action:" + actionNames[currentActionID] + "with length" + (waitTime + countdown).asString +
			"sec and transition:" + transitions[transitionNbr][0] + "with length" + transitionTime + "sec\n");

		// count up - waiting for next loop
		counting = 0;
		while(
			{ counting < waitTime && nextAction == 0},
			{
				if(showCount == 1, {(waitTime - counting).postln});
				1.wait;
				counting = counting + 1;
		});
		// set button to 'CANCEL'
		{bCancelNext.value = 0}.defer(0.2);
		// log next part
		if(nextAction == 1, { fileSaveLog.write(Date.getDate.asString + "<nextAction>\n") });
	};
},
actionsClock);

transitionTask = Task({
	var step = 10; // divide a second in these number of steps for the fader
	var nextActionText = displayNextAction.states[0][0];
	// show fader
	{ transitionFader.visible = true }.defer;
	// run fader
	(transitionTime * step).do {|countTransition|
		transitionFader.value = 1 - ((countTransition + 1) / (transitionTime * step) );
		// only send out OSC once per second
		if(countTransition%step == 0, {
			fMessaging.value("transition", "", transitionTime - (countTransition / step));
		});
		// wait
		(1/step).wait;
		// flicker next action
		// if(countTransition%(2*step) == 0, { displayNextAction.states = [[nextActionText]] });
		// if(countTransition%(2*step) == (1.5*step).floor, { displayNextAction.states = [[""]] });
	};
	fMessaging.value("transition", "", 0);
	{ // hide fader and update current and next actions
		transitionFader.visible = false;
		displayCurrentAction.states = [[actionNamesAlt[currentActionID].asString]];
		displayNextAction.states = [[""]];
	}.defer;
}, transitionClock);

// to run the generator automatically
tGenerateAuto = Task {
	inf.do {
		"\n---> AutoRun Generator running".postln;
		if(countUp == 0, { { bCancelNext.valueAction = 0 }.defer(0.2) });
		(countdown + 6).wait;
	};
};

///////////////////////////////////////////// status window //////////////////////////////////////

// window layout
rect.move = -20;
rect.window = Rect(280, (screenHeight - (600 + (2*winAdd))), 480 + (2*winAdd), 355 + rect.move + (2*winAdd));
rect.currentActionLabel = Rect(5 +  winAdd, 5 +  winAdd, 205, 30);
rect.currentAction = Rect(5 +  winAdd, 35 +  winAdd, 205, 50);
rect.transitionLabel = Rect(215 +  winAdd, 5 +  winAdd, 50, 40);
rect.transition = Rect(215 +  winAdd, 43 +  winAdd, 50, 40);
rect.nextActionLabel = Rect(270 +  winAdd, 5 +  winAdd, 205, 30);
rect.nextAction = Rect(270 +  winAdd, 35 +  winAdd, 205, 50);
rect.transitionitionFader = Rect(5 +  winAdd, 120 + rect.move + winAdd, 470, 20);
rect.cancelNext = Rect(5 +  winAdd, 200 + rect.move + winAdd, 420 - (showClock*138), 70);
rect.clock1 = Rect(292 +  winAdd, 200 + rect.move + winAdd, 132, 70);
rect.remote = Rect(430 +  winAdd, 238 + rect.move + winAdd, 45, 32);
rect.start = Rect(430 +  winAdd, 200 + rect.move + winAdd, 45, 32);
rect.actionChooser = Rect(380 +  winAdd, 330 + rect.move + winAdd, 95, 20);
rect.oSCin = Rect(5 +  winAdd, 330 + rect.move + winAdd, 75, 20);
rect.oSCout = Rect(85 +  winAdd, 330 + rect.move + winAdd, 75, 20);

font.currentAction = Font("Helvetica",30, true);
font.transition = Font("Helvetica",40, true);
font.nextAction = Font("Helvetica",30, true);
font.cancelNext = Font("Helvetica",30, true);
font.clock1 = Font("Helvetica",30, true);
font.small =  Font("Helvetica",10);
font.regular =  Font("Helvetica",10);

// define window
wActionGenerator = (Window("Shackle System Version 2", rect.window, resizable: true)
	.background_(Color.white(0.9))
);
// action displays
StaticText(wActionGenerator, rect.currentActionLabel).font_(font.small).string_("Current action");
displayCurrentAction = (SmoothButton(wActionGenerator, rect.currentAction)
	.border_(1).radius_(3).canFocus_(false)
	.font_(font.currentAction).background_(Color.white).states_([[""]])
);
StaticText(wActionGenerator, rect.transitionLabel).font_(font.small).string_("Transition").align_(\center);
displayTransition = (StaticText(wActionGenerator, rect.transition)
	.font_(font.transition).background_(Color.white).align_(\center)
	.string_("")
);
StaticText(wActionGenerator, rect.nextActionLabel).font_(font.small).string_("Next action").align_(\right);
displayNextAction = (SmoothButton(wActionGenerator, rect.nextAction)
	.border_(1).radius_(3).canFocus_(false)
	.font_(font.nextAction).background_(Color.white).states_([[""]])
);
transitionFader = (SmoothSlider(wActionGenerator, rect.transitionitionFader)
	.hilightColor_(Color(0.0, 0.0, 0.7, 0.5)).background_(Color.blue.alpha_(0))
	.knobColor_(Color.white).knobSize_(0)
	.border_(0).borderColor_(Color.grey(0.4))
	.canFocus_(false).value_(1).visible_(false)
	.string_("   transitioning...")
);

// cancel / next button
bCancelNext = (SmoothButton(wActionGenerator, rect.cancelNext)
	.border_(1).radius_(3).font_ (font.cancelNext).canFocus_(false)
	.states_([["CANCEL", Color.black, Color.white],["NEXT", Color.black, Color.white]])
	.action_({
		if(bCancelNext.value == 1, { // cancel
			nextAction = 0;
			cancelAction = 1;
			{ fMessaging.value("action", 0) }.defer();
			cancelActionClock = AppClock.sched(2,{cancelAction = 0; fMessaging.value("clear"); nil});
		},{ // next
			cancelAction = 0;
			nextAction = 1;
			{ fMessaging.value("action", 1) }.defer();
			nextActionClock = AppClock.sched(2, { nextAction = 0; nil });
		});
	})
);

// clock
if(showClock == 1, {
	displayClock = (SmoothButton(wActionGenerator, rect.clock1)
		.border_(1).radius_(3).canFocus_(false)
		.font_(font.clock1).background_(Color.white).states_([["00:00"]])
	);
});

// switch for remoteClientsOnline
if(onLine == 1, {
	bRemoteClientsOnline = (SmoothButton(wActionGenerator, rect.remote)
		.border_(1).radius_(3).canFocus_(false)
		.states_([["OFFLINE", Color.black, Color.white],["ONLINE", Color.black, signalColor]])
		.font_(font.small).value_(remoteClientsOnline)
		.action_({
			remoteClientsOnline = (remoteClientsOnline+1)%2;
			~shackleRemoteClientsOnline = remoteClientsOnline;
			("\nSwitching remote clients" + if(remoteClientsOnline==1, {"ONLINE"}, {"OFFLINE"})).postln;
		})
	);
});

// start and stop generator
bRun = (SmoothButton(wActionGenerator, rect.start)
	.border_(1).radius_(3).canFocus_(false).font_ (font.regular)
	.states_([["RUN", Color.black, Color.white],["STOP", Color.white, Color.black]])
	.action_({
		if(bRun.value == 1, { // START
			actionChooser.value_(0); // set action chooser to 0
			actionChooser.enabled_(false);
			countUp = 0;  // reset countUp in case we stopped during countUp
			cancelAction = 0; // reset cancel flag in case we stopped during cancellation
			fMessaging.value("start", 1);
			firstCountdown = 1;
			if(showClock == 1, {
				displayClock.states = [["00:00"]];
				tNewClock = Task(fNewClock).play;
			});
			tActionGenerator.start;
			fileSaveLog = File(logFile, "a"); // open logfile
			fileSaveLog.write("\n" ++ Date.getDate.asString + "Generator started\n");
		},{ // STOP
			tActionGenerator.stop;
			fileSaveLog.write(Date.getDate.asString + "Generator stopped\n");
			fileSaveLog.close; // close logfile
			if(showClock == 1, { tNewClock.stop });
			fMessaging.value("start", 0);
			actionsClock.clear;
			transitionClock.clear;
			transitionFader.visible_(false).value_(1);
			bCancelNext.value= 0; // reset next/cancel button to cancel
			displayNextAction.states = [[""]];
			actionChooser.enabled_(true);
			actionChooser.focus;
			actionChooser.valueAction_(currentActionID - 1); // activate current action
		});
	})
);

// OSC monitor
bOSCin = (SmoothButton(wActionGenerator, rect.oSCin)
	.border_(1).radius_(3).font_(font.regular).canFocus_(false)
	.states_([ ["OSC in"], ["OSC in",Color.black, Color.green] ])
	.action_({ |button|
		if(button.value==1,
			{ thisProcess.oscInMonitor(true, addr:1, excl: ['/InBus','/hid/ex3d', '/ard/ana', '/midi/control']) },
			{ thisProcess.oscInMonitor(false) });
	})
);
bOSCout = (SmoothButton(wActionGenerator, rect.oSCout)
	.border_(1).radius_(3).font_(font.regular).canFocus_(false)
	.states_([ ["OSC out"], ["OSC out",Color.black, Color.green] ])
	.action_({ |button|
		if(button.value==1, { ~oscOutMonitor = 1 }, { ~oscOutMonitor = 0 } )
	})
);

actionChooser = (PopUpMenu(wActionGenerator, rect.actionChooser)
	.canFocus_(true).items_(actionChooserNames).background_(signalColor).font_ (font.small)
	.action_({
		currentActionID = actionChooser.value + 1;
		{ fMessaging.value("new", currentActionID, "", 0) }.defer();
	})
	.keyDownAction_({
		arg view, char, modifiers, unicode, keycode;
		if((keycode == 125 && actionChooser.enabled), { // page down -> next action
			if(actionChooser.value == (actionChooserNames.size-1),
				{ actionChooser.valueAction_(0) },
				{ actionChooser.valueAction_(actionChooser.value + 1) });
		});
		if((keycode == 126 && actionChooser.enabled),{ // page up -> prev action
			if(actionChooser.value == 0,
				{ actionChooser.valueAction_(actionChooserNames.size-1) },
				{ actionChooser.valueAction_(actionChooser.value - 1) });
		});
		false
}));

wActionGenerator.view.keyDownAction_({
	arg view, char, modifiers, unicode, keycode;
	// [keycode, modifiers].postln;
	if(keycode == 17 && modifiers.isAlt, {
		if (countdown == countdownDefault, {
			countdown = 5;
			"Countdown set to 5".postln;
			{ countdown = countdownDefault; "Countdown reset".postln; }.defer(6);
		});
	});
	// if spacebar pressed and counting up in task, cancel part
	if(((keycode == 49) && (countUp != 0)),
		{ { bCancelNext.valueAction = 1 }.defer(0.2) });
	// if spacebar is pressed and we're not counting up in task, call next part
	if(((keycode == 49) && (countUp == 0)),
		{ { bCancelNext.valueAction = 0 }.defer(0.2) });
	// alt-g: start to run generator automatically
	if((keycode == 5) && (modifiers.isAlt),
		{ if(tGenerateAuto.isPlaying,
			{ tGenerateAuto.stop; "\nStop AutoRun Generator".postln },
			{ tGenerateAuto.start; "\nStart AutoRun Generator".postln });
	});
	// key f -> fullscreen
	if((keycode == 3) && (modifiers == 0),{
		if(wActionGenerator.fullScreen == 0, { wActionGenerator.fullScreen }, { wActionGenerator.endFullScreen });
	});
	// alt-o -> switch remoteClientsOnline
	if((keycode == 31) && (modifiers.isAlt) && (onLine == 1),
		{ bRemoteClientsOnline.valueAction_((bRemoteClientsOnline.value+1)%2) });
});

wActionGenerator.front;
wActionGenerator.onClose_({
	tActionGenerator.stop;
	tGenerateAuto.stop;
	if(showClock == 1, {tNewClock.stop});
	if(notNil(fileSaveLog), {fileSaveLog.close});
	OSCdef(\shackSysCancelNext).free;
	if(client1.notNil, {client1.disconnect});
	lapisStat.stop;
	nextActionClock.clear;
	cancelActionClock.clear;
	transitionClock.clear;
	actionsClock.clear;
});

// include LapisStatus GUI
lapisStat = LapisStatus.new(5+winAdd,270+winAdd,25, wActionGenerator);

///////////////////////////////////////////// initialize  //////////////////////////////////////

fOscResponder.value();
)




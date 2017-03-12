// Shackle System / Parts Clientdocuent
// by Robert van Heumen 2007/2012/2014

// Working with SC 3.6.6

(

///////////////////////////////////////////// definition variables //////////////////////////////////////

// user settings

var projectID = 0; // current project, index into project.name
var project = (
	name: [\ShackleAffair,\ConvergingObjects,\TubesInChains, \NightCall, \SundayRhino, \SacredNoise,\CvA],
	nbrOfParts: [24,21,13,8,10,9,13],	// including CANCEL/NEXT/END
	fiNotes: ["notesExt.txt","notes.txt","notesGeneric.txt","notesGeneric.txt","notesGeneric2.txt","notesGeneric.txt","notes.txt"],
	fiConfig: ["config.txt","config.txt","config.txt","config.txt","config.txt","config.txt","config.txt"]
);

var version = "4.6";
var mode = "iPad";
//var mode = "Big Screen"; // 1280x1024
var scale = case {mode == "iPad"} {1.1} {mode == "Big Screen"} {1.85};
var showClock = 0;

var dataLib = Document.dir++"Shackle/Data/ShackleSystem/";
var serverListenPort = 57120;
var clientListeningPort = 57120;
var serverIP = "127.0.0.1";
var signalColor = Color.green(0.9), colorBlank = Color.grey(0.3);

// general settings
var serverTo = NetAddr(serverIP,serverListenPort);
var serverFrom = NetAddr(serverIP,clientListeningPort);
var firstCountdown = 1, nbrOfParts, fiNotes, fiConfig, countup = 0, systemRunning = 0;

// GUI etc
var wPartsClient, dispPart, dispPartNext, dispPartNote, projectChooser, dispShackle, dispPartNoteCanvas, keyCatcher;
var partNext, partNote, tmpNote, fiReadNotes, fReadNotes, partNames, fReadConfig, fiReadConfig, partNbr;
var fNewClock, tNewClock, dispClock;


///////////////////////////////////////////// OSC responder //////////////////////////////////////

OSCdef(\shackSysCliePart, { arg message;
	{
		partNbr = message[1];
		dispPart.states = [[partNames[message[1]]]];
		dispPartNext.states = [[""]];
		dispPartNote.string = partNote[message[1]];
		//		dispPartNote.string = " " ++ partNames[message[1]] ++ ":\n" ++ partNote[message[1]];
		// restart clock
		if(systemRunning==1, {
			tNewClock.stop;
			dispClock.states = [["00:00"]];
			tNewClock = Task(fNewClock).play;
		});
	}.defer;
	countup = 0;
}, "/part").fix;

OSCdef(\shackSysCliePartNext, { |message|
	case
	{message[1] == 0} // cancel
	{{
		dispPartNext.states = [["<cancelled>"]];
		AppClock.sched(2,{dispPartNext.states = [[""]]; nil});
		AppClock.sched(0.5,{dispPartNote.background_(Color.white); nil});
		countup = 0;
		if(firstCountdown==0, { // reset to previous part numner
			AppClock.sched(0.5,{dispPartNote.string = partNote[partNbr]; nil});
		},
		{ // on first countdown clear notes plus backgroundimage
			AppClock.sched(0.5,{dispPartNote.string = ""; nil});
		});
	}.defer;}
	{message[1] == 1} // next
	{{
		//			dispPartNext.states = [["<next_part>"]];
		//			AppClock.sched(0.5,{dispPartNext.states = [[""]]; nil});
	}.defer;}
	{message[1] >= 2} // part next
	{{
		// blink next part
		dispPartNext.states = [[partNames[message[1]] ++ "(" ++ countup ++ ")"]];
		dispPartNext.background_(signalColor);
		dispPartNote.background_(signalColor);
		AppClock.sched(0.5,{dispPartNext.states = [[""]]; nil});
		AppClock.sched(0.5,{dispPartNext.background_(Color.white); nil});

		// display note part next
		dispPartNote.string = partNote[message[1]];
		//			dispPartNote.string = " " ++ partNames[message[1]] ++ ":\n" ++ partNote[message[1]];
	}.defer;}
}, "/part_next").fix;

OSCdef(\shackSysCliePartCount, { arg message;
	countup = message[1];
	// when counted down completely, first countdown is done
	if((countup == 1) && (firstCountdown == 1), {firstCountdown = 0; "Responder: just finished first countdown".postln});
	if(countup == 1, {AppClock.sched(0.5,{dispPartNote.background_(Color.white); nil})});
}, "/count").fix;

OSCdef(\shackSysClieStart, { arg message;
	// on start clear 'current part'
	{dispPart.states = [[""]]}.defer();
	systemRunning = message[1];
	if(systemRunning==0, {
		tNewClock.stop;
		dispClock.states = [["00:00"]];
	});
	("System is"+if(systemRunning==0, {"stopped"},{"running"})).postln;
}, "/start").fix;


///////////////////////////////////////////// functions //////////////////////////////////////

// read in notes for parts
fReadNotes =
{
	"READING NOTES...".postln;

	if(File.exists(fiNotes),
		{
			fiReadNotes = File(fiNotes,"r");
			k = -1;
			partNote = Array.newClear(nbrOfParts);
			partNote.fill("");

			// keep reading while we still have parts
			while( {k <= (nbrOfParts - 1)},
				{
					tmpNote = fiReadNotes.getLine(200).asString;
					// starting with * means partnumber & name
					if( (tmpNote.subStr(0,1) == "<*"),
						{ k = k + 1; },
						{
							// starting with +++ means end of file
							if(tmpNote.subStr(0,2) == "+++",
								{ k = nbrOfParts; },
								{ partNote[k] = partNote[k] + tmpNote + "\n"; });
					});
			});

			fiReadNotes.close;
			partNote.postln;
		},
		{("!!NOTES" + fiNotes + "NOT FOUND!!").postln});
};

// read in config file - part names
fReadConfig =
{
	"READING CONFIG...".postln;

	partNames = Array.newClear(nbrOfParts);

	if(File.exists(fiConfig),
		{
			fiReadConfig = File(fiConfig,"r");
			nbrOfParts.do({ |i|
				partNames[i] = fiReadConfig.getLine(200); // part name
				fiReadConfig.getLine(200);
				fiReadConfig.getLine(200);
				fiReadConfig.getLine(200);
				fiReadConfig.getLine(200);
				fiReadConfig.getLine(200);
				fiReadConfig.getLine(200);
			});
			fiReadConfig.close;
		},
		{("!!CONFIG" + fiConfig + "NOT FOUND!!").postln}
	);

	// display parameters
	("Part Names:  " + partNames).postln;

};

fNewClock = {
	var tick = 0;
	inf.do({
		1.wait;
		tick = tick + 1;
		{dispClock.states = [[tick.asTimeStringHM]]}.defer();
	});
};

///////////////////////////////////////////// control window //////////////////////////////////////

wPartsClient = Window("Shackle System |" + mode + "Client" + version, Rect(10, 2000, scale*700, scale*500))
.background_(Color.white);

keyCatcher = UserView(wPartsClient,Rect(0,0,3000,3000)); // to catch keystrokes

dispPart = SmoothButton(wPartsClient, Rect(10, 10, scale*330, scale*80))
.radius_(3)
.border_(1)
.states_([["..."]])
.canFocus_(false)
.background_(Color.white)
.font_(Font("Helvetica",scale*45, true));

dispPartNext = SmoothButton(wPartsClient, Rect(scale*360, 10, scale*330, scale*80))
.radius_(3)
.border_(1)
.states_([["..."]])
.canFocus_(false)
.background_(Color.white)
.font_(Font("Helvetica",scale*45, true));

projectChooser = PopUpMenu(wPartsClient, Rect(10, scale*105, max(120, scale*100), 20));
projectChooser.items = project.name;
projectChooser.canFocus = false;
projectChooser.background_(signalColor);
projectChooser.font_(Font("Helvetica",min(12,max(9,(scale*6.5).round))));
projectChooser.action = {
	projectID = projectChooser.value; // current project
	nbrOfParts = project.nbrOfParts[projectID];
	fiNotes = dataLib++project.name[projectID]++"/"++project.fiNotes[projectID];
	fiConfig = dataLib++project.name[projectID]++"/"++project.fiConfig[projectID];
	fReadNotes.value();
	fReadConfig.value();
};

dispShackle = StaticText(wPartsClient, Rect(scale*530, scale*105, scale*250, 20))
.canFocus_(false)
.string_("Shackle System | Receive Program | 2014")
.font_(Font("Helvetica",min(12,max(9,(scale*6.5).round))))
.setProperty(\align,\right);

dispClock = (SmoothButton(wPartsClient, Rect(scale*300, scale*95, scale*100, scale*30))
	.border_(1)
	.radius_(3)
	.visible_(showClock==1)
	.canFocus_(false)
	.font_(Font("Helvetica",scale*25))
	.background_(Color.white)
	.states_([["00:00"]])
);

dispPartNoteCanvas = TextView(wPartsClient, Rect(10, scale*135, scale*683, scale*350));
dispPartNoteCanvas.background = colorBlank;

dispPartNote = TextView(wPartsClient, Rect(11, scale*135.7, scale*681.8, scale*348.5))
.hasVerticalScroller_(false);
dispPartNote.canFocus = false;
dispPartNote.background_(Color.white);
dispPartNote.font = Font("Helvetica",scale*45, true);

// initialize
projectChooser.value_((projectID+1)%(project.name.size-1)); // first set value something else
projectChooser.valueAction_(projectID); // then we're sure valueAction actually does the action

wPartsClient.view.keyDownAction_({
	arg view, char, modifiers, unicode, keycode;
	// spacebar pressed
	if(keycode == 49, {
		if(countup != 0,
			{
				serverTo.sendMsg("/cancel");
				countup = 0;
			},
			{
				serverTo.sendMsg("/next");
		});
	});
});
//wPartsClient.background_(Color.white);
wPartsClient.front;

wPartsClient.onClose_({
	tNewClock.stop;
	OSCdef(\shackSysCliePartNext).free;
	OSCdef(\shackSysCliePart).free;
	OSCdef(\shackSysCliePartCount).free;
	OSCdef(\shackSysClieStart).free;
});


)




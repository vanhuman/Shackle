// Shackle System / Parts Client
// by Robert van Heumen 2007/2012

// Working with SC 3.6.6

(

///////////////////////////////////////////// definition variables //////////////////////////////////////

// user settings
var projectID = 2; // current project, index into project.name
var project = (
	name: [\ShackleAffair,\ConvergingObjects,\DetuningGuitar,\SundayRhino, \SacredNoise],
	nbrOfParts: [24,21,13,10,9],	// including CANCEL/NEXT/END
	fiNotes: ["notesExt.txt","notes.txt","notesExt.txt","notesGeneric.txt","notesGeneric.txt"],
	fiConfig: ["config.txt","config.txt","config.txt","config.txt","config.txt"]
);

var version = "4.5";
var scale = 1.35;
var serverListenPort = 57120, clientListeningPort = 57120, serverIP = "127.0.0.1";
var imageBase = "/Data/images/", dataLib = Document.dir++"Shackle/Data/ShackleSystem/";
var colorBlue = Color.new255(0,0,135), colorGreen = Color.new255(37,137,70), colorBlink = colorGreen, colorBlank = Color.grey(0.3),
colorBack = Color.grey(0.9);

// general settings
var serverTo = NetAddr(serverIP,serverListenPort);
var serverFrom = NetAddr(serverIP,clientListeningPort);
var fiConfig, fiNotes, nbrOfParts, firstCountdown = 1;
var countup = 0, partNext, partNote, tmpNote, fiReadNotes, fReadNotes, partNames, fReadConfig, fiReadConfig, partNbr;

// GUI
var wPartsClient, dispPart, dispPartNext, projectChooser, keyCatcher;
var dispPartNextCanvas, dispPartCanvas, countAlert, captionText, blinkAlert, arrowImageNext, arrowImage;

///////////////////////////////////////////// OSCdefs //////////////////////////////////////

OSCdef(\shackSysClieExtPart, { arg message;
	{
		partNbr = message[1];
		// update interface
		if(partNote[message[1]].notNil, {dispPart.string = partNote[message[1]]},{dispPart.string = "\n <PART NOT AVAILABLE>"});
		dispPartNext.string = "";
		countAlert.states = [[""]];
		colorBlink = colorGreen;
		arrowImage.visible_(true);
		dispPartNextCanvas.background_(colorBlank);
		blinkAlert.background_(colorGreen);
	}.defer;
	countup = 0;
}, "/part").fix;

OSCdef(\shackSysClieExtPartNext, { arg message;
	case
	{message[1] == 0} // cancel
	{{
		dispPartNext.string = "\n <CANCELLED>";
		colorBlink = colorGreen;
		arrowImage.visible_(true);
		countup = 0;
		// clear count/next
		countAlert.states = [[""]];
		dispPartNextCanvas.background_(colorBlank);
		blinkAlert.background_(colorGreen);
		AppClock.sched(0.5,{blinkAlert.background_(colorGreen); nil});
		AppClock.sched(2,{if(firstCountdown == 0, {dispPartNext.string = ""}); nil});
	}.defer;}
	{message[1] == 1} // next
	{{
		colorBlink = Color.white;
	}.defer;}
	{message[1] >= 2} // part next
	{{
		// display next part
		if(partNote[message[1]].notNil, {dispPartNext.string = partNote[message[1]]},{dispPart.string = "\n <PART NOT AVAILABLE>"});
	}.defer;};
}, "/part_next").fix;

OSCdef(\shackSysClieExtPartCount, { arg message;
	countup = message[1];

	// update interface
	{
		colorBlink = Color.white;
		arrowImage.visible_(false);
		blinkAlert.background = colorBlue;
		dispPartNextCanvas.background_(colorBlue);
		countAlert.states = [[if(countup<10, {"" + countup},{countup.asString})]];
		arrowImageNext.visible_(true);
	}.defer();
	AppClock.sched(0.5,{blinkAlert.background_(colorBlink); arrowImageNext.visible_(false); nil});

	// when counted down completely, first countdown is done
	if((countup == 1) && (firstCountdown == 1), {firstCountdown = 0; "\nResponder: just finished first countdown".postln});
}, "/count").fix;

OSCdef(\shackSysClieExtStart, { arg message;
	// on start clear 'current part'
	case
	{message[1] == 1} // start
	{{
		dispPart.string = "";
		colorBlink = Color.white;
	}.defer()}
	{message[1] == 0} // stop
	{{
		countAlert.states = [[""]];
		dispPartNextCanvas.background_(colorBlank);
		dispPartNext.string = "";
		colorBlink = Color.white;
		firstCountdown = 1;
	}.defer()}
	;
}, "/start").fix;


///////////////////////////////////////////// functions //////////////////////////////////////

// read in notes for parts
fReadNotes =
{
	"\nREADING NOTES...".postln;

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
			// partNote.postln;
		},
		{("\n!!NOTES" + fiNotes + "NOT FOUND!!").postln});
};

// read in config file - part names
fReadConfig =
{
	"\nREADING CONFIG...".postln;

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
		{("\n!!CONFIG" + fiConfig + "NOT FOUND!!").postln}
	);

	// display parameters
	("\nPart Names:  " + partNames).postln;

};

///////////////////////////////////////////// control window //////////////////////////////////////

wPartsClient = Window("Shackle System | Receive Program" + version, Rect(10, 2000, scale*780, scale*580))
.background_(Color.white);

keyCatcher = UserView(wPartsClient,Rect(0,0,3000,3000)); // to catch keystrokes

captionText = SmoothButton(wPartsClient, Rect(20, 20, scale*280, scale*30))
.border_(1)
.radius_(3)
.canFocus_(false)
.states_([["Shackle System | Receive Program  | 2014"]])
.font_(Font("Helvetica",max(9,round(scale*10))))
.background_(colorBack);

projectChooser = PopUpMenu(wPartsClient, Rect(20, scale*60, max(120, scale*100), 20))
.items_(project.name)
.canFocus_(false)
.background_(colorBack)
.font_(Font("Helvetica",min(12,max(9,(scale*6.5).round))))
.action_({
	projectID = projectChooser.value; // current project
	nbrOfParts = project.nbrOfParts[projectID];
	fiNotes = dataLib++project.name[projectID]++"/"++project.fiNotes[projectID];
	fiConfig = dataLib++project.name[projectID]++"/"++project.fiConfig[projectID];
	fReadNotes.value();
	fReadConfig.value();
});

blinkAlert = SmoothButton(wPartsClient, Rect(scale*430, 20, scale*140, scale*140))
.border_(1)
.radius_(3)
//	.states_([[""]])
.canFocus_(false)
.background_(colorGreen);

countAlert = SmoothButton(wPartsClient, Rect(scale*604, 20, scale*140, scale*140))
.border_(1)
.radius_(3)
.canFocus_(false)
.states_([[""]])
//	.background_(colorBack)
.font_(Font("Helvetica",scale*110, true));

arrowImageNext = UserView(wPartsClient, Rect(scale*60, scale*160, 100,100));
arrowImageNext.drawFunc = { DrawIcon( \down, Rect(0,0,50,50)) };
arrowImageNext.visible_(false);

dispPartNextCanvas = QTextView(wPartsClient, Rect(18, scale*199, scale*743, scale*152));
dispPartNextCanvas.background = colorBlank;

dispPartNext = TextView(wPartsClient, Rect(20, scale*200, scale*740, scale*150))
.hasVerticalScroller_(false)
.string_("")
.canFocus_(false)
.background_(Color.white)
.font_(Font("Helvetica",scale*40, true));

arrowImage = UserView(wPartsClient, Rect(scale*60, scale*360, 100,100));
arrowImage.drawFunc = { DrawIcon( \down, Rect(0,0,50,50)) };
arrowImage.visible_(true);

dispPartCanvas = TextView(wPartsClient, Rect(18, scale*399, scale*743, scale*152));
dispPartCanvas.background = colorGreen;

dispPart = TextView(wPartsClient, Rect(20, scale*400, scale*740, scale*150))
.hasVerticalScroller_(false)
.string_("")
.canFocus_(false)
.background_(Color.white)
.font_(Font("Helvetica",scale*40, true));

// initialize
projectChooser.value_((projectID+1)%(project.name.size-1)); // first set value something else
projectChooser.valueAction_(projectID); // then we're sure valueAction actually does the action

wPartsClient.view.keyDownAction_({
	arg view, char, modifiers, unicode, keycode;
	// [modifiers,keycode].postln;
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
wPartsClient.front;

wPartsClient.onClose_({
	OSCdef(\shackSysClieExtPartNext).free;
	OSCdef(\shackSysClieExtPart).free;
	OSCdef(\shackSysClieExtPartCount).free;
	OSCdef(\shackSysClieExtStart).free;
});


)




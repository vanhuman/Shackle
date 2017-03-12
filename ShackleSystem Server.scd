// ShackleSystem: Shackle Electro Acoustic Composition System / Parts Generator
// by Robert van Heumen 2007-2014
// Working with SC 3.6.6

// OSC messaging protocol
// --- sending ---
// while counting down next proposal:
//			"/part_next", part nbr
//			"/count", countdown number
//			"/part_trans", transition nbr
//			"/contralayer", contrapuntal layer number
// when part is chosen: "/part", part nbr
// when countdown cancelled: "/part_next", 0
// when next part is proposed: "/part_next", 1
// when part allows control by Robert of Anne's parameters: "/rct", value and "/rsw", value
// when new film bit is required: "/bit", bit number
// when film bits should be shown/hidden: "/bit_enable", 0/1 and "/bit_alpha", 0/1
// --- receiving ---
// to cancel countdown: "/cancel"
// to request next part: "/next"
// one switch for cancel/next: "/cancelnext"
// when part allows control by Anne of Robert's parameters: "/act", value

// parts: make sure the config and notes files are configured correctly: 1st part is CANCEL, 2d part is NEXT, last part is END
// part names are taken from the config file, the parts in the notes file should be in the same order with a header starting with <*

// TODO -----------------------
// revise array logic in config (normalizeSum etc)

( // main loop

/////////////////////////////////////////////  variables //////////////////////////////////////

// user settings
var pID = if(~pShackleSystemID.notNil, {~pShackleSystemID},{0}); // project ID, index into project.name
var project = (
	name: [\Shackle,\ShackleAffair, \ConvergingObjects,\NightCall,\TubesInChains,
								\RVH,\DetuningGuitar,\SundayRhino,\SacredNoise,\CvA],		// determines which notes and config files to load
	setLength: [120*60,30*60,10*60,15*60,0,0,20*60,20*60,20*60,20*60],		// 0=no end, other than 0 sets the time in minutes after which the last part is shown
	dupAllowed: [1,1,0,0,1,1,0,1,1,1],				 			// if 0 then all parts will come by once before they are repeated
	nbrOfParts: [27,24,21,8,13,14,13,10,9,13],			   	// inclusief 0=CANCEL 1=NEXT laatste=END
	initialPart: [0,0,0,0,2,7,0,2,2,0],				           		// if 0 then random
	hybridReceiveParts: [[14],[],[],[],[],[],[],[],[],[]],	   		// respond to received control data for these parts (LIMIT)
	hybridSendParts: [[8,20],[],[],[],[],[],[],[],[],[]],				// send control data for these parts (CLIP, SNAP)
	coverTunes: [[],[],[],[],[],[],[],[],[],[]],							// part numbers of cover tunes
	coverTimes: [[15*60],[],[],[],[],[],[],[],[],[]],					// time before the cover tune should be started, in seconds
	coverStarted: [[0],[],[],[],[],[],[],[],[],[]], 						// switch to keep track of the cover tune has been played or not
	fontPartnote: [Font("Helvetica",25), Font("Helvetica",25), Font("Helvetica",30, true), Font("Helvetica",25),Font("Helvetica",25),
								Font("Helvetica",20),Font("Helvetica",28),Font("Helvetica",25),Font("Helvetica",25),Font("Helvetica",25)],
	enableRemoteCancelNext: [1,1,1,1,0,0,1,0,0,1],	// remote cancel/next enabled (1) disabled (0)
	sendBits: [0,0,0,0,0,0,0,0,0,0],									// whether to send OSC to trigger film, 0=off, 1=on
	onLine: [1,1,0,0,0,0,0,0,0,0],									// whether to show button to switch cfg.remoteClientsOnline
	contraLayer: [1,0,0,0,0,0,0,0,0,0],							// whether to show the contraLayers
	midiReceiveParts: [[],[],[],[],[],[],[],[8],[],[]],				// the parts the midi receive from the Sauer organ will be enabled for
	midiSendParts: [[],[],[],[],[],[],[],[2,4],[],[]], 					// the parts the midi send to the Sauer organ will be enabled for
	noSampling: [0,1,0,0,0,0,0,0,0,0]							// when 1 this will receive OSC /albon and /alboff and colorize the background
);

var cfg = (
	version: "6.4",

	endPart: nil, 					// part number for END
	maxLenAbs: 300, 			// max length sliders in config
	showClock: 0,					// whether to show clock or not - if setLength != 0 then this will be set to 1 below
	showCards: 0,					// whether to show Shackle Deck cards
	cardColor: 1, 					// 0=blue 1=white 2=recycled
	winAdd: 0, 						// add to width & height of the window, centering the contents
	showCount: 0,					// show counting seconds in post window
	countdown: 15,				// the number of countdown seconds
	genFactor: 1,  					// the factor the wait times are divided by to change the part generation speed
	cancelFactor: 2,  				// the factor the wait times are divided by after cancelling
	hybridOn: 1,						// this will be set below depending on hybridReceiveParts and hybridSendParts
	coverReschedule: 5*60, 	// time to delay a cancelled cover tune

	remoteClientsOnline: 0,	// when 0 no OSC msg will be send to clients below which are not local
	client1: NetAddrMon("169.254.0.1", 57121),  	// to Anne
	client2: NetAddr("127.0.0.1", 57121),		// to localhost for QC, to monitor outgoing OSC, set ~oscOutMonitor to 1
	client3: NetAddrMon("127.0.0.1", 57120), 				// to localhost for SC
	// client3: NetAddr("169.254.0.5", 57121), 		// to a third remote player
	localAddr: NetAddr("127.0.0.1", 57120),			// to communicate with other SC programs (f.e. LiveSampler)
	// netaddrTouchOSC: NetAddrMon("169.254.0.6", 9000),  	// to iPad running TouchOSC

	dataDir: Document.dir++"Shackle/Data/ShackleSystem/",
	transitionList: ["free", "hardcut", "crossfade"],
	transitionSymbolList: ["--", "|", "X"],
	contraLayerList: ["amplitude gate", "arrhythmic", "compress time", "crunchy", "expand time", "groove","high pass filter", "invert", "glue", "smooth", "staccato"],

	textCancel: "<cancelled>",   				// value displayed when cancel received
	textNext: "<next_part>",   					// value displayed when next part is requested
	receivingCancel: "/cancel",  				// cancel value received from other player
	receivingNext: "/next",  						// next part value received from other player
	receivingCancelNext: "/cancelnext",  	// cancelnext value received from other player
	receivingCtr: "/act", 								// controller value received from other player
	receivingScale: 1010, 							// range of value received from other player
	sendingCtr: "/rct", 								// controller value send to other player
	sendingSw: "/rsw", 								// switch value send to other player

	// working vars filled with the project data from above
	project: project.name[pID],
	nbrOfParts: project.nbrOfParts[pID],
	initialPart: project.initialPart[pID],
	hybridReceiveParts: project.hybridReceiveParts[pID],
	hybridSendParts: project.hybridSendParts[pID],
	coverTunes: project.coverTunes[pID],
	coverTimes: project.coverTimes[pID],
	coverStarted: project.coverStarted[pID],
	setLength: project.setLength[pID],
	dupAllowed: project.dupAllowed[pID],
	fontPartnote: project.fontPartnote[pID],
	enableRemoteCancelNext: project.enableRemoteCancelNext[pID],
	sendBits: project.sendBits[pID],
	onLine: project.onLine[pID],
	contraLayer: project.contraLayer[pID],
	midiReceiveParts: project.midiReceiveParts[pID],
	midiSendParts: project.midiSendParts[pID],
	noSampling: project.noSampling[pID]
);

var file = (
	notes: cfg.dataDir ++ cfg.project ++ "/notes.txt", 	// notes file
	config: cfg.dataDir ++ cfg.project ++ "/config.txt", 	// config file
	configBackup: cfg.dataDir ++ cfg.project ++ "/backup/config.txt", 	// config backup file
	log: cfg.dataDir ++ cfg.project ++ "/log.txt" 			// log file
);

// support for receiving/sending MIDI from external source
var midiReceiveEnabled = 0;
var midiSendEnabled = 0;

// part arrays
var partSpec = Array.new(cfg.nbrOfParts), partNote = Array.new(cfg.nbrOfParts);
var partNbrs = Array.new(cfg.nbrOfParts), partNames = Array.new(cfg.nbrOfParts);
var partMinLen = Array.new(cfg.nbrOfParts), partMaxLen = Array.new(cfg.nbrOfParts);
var partWeight = Array.new(cfg.nbrOfParts), partTotWeightNext = Array.newClear(cfg.nbrOfParts);
var partWeight_next = Array.newClear(cfg.nbrOfParts + 1); 		// +1 for the initial, default weights
var partsDone = Array.new(cfg.nbrOfParts), partsTemp = Array.new(cfg.nbrOfParts);
var partChooserNames = Array.new(cfg.nbrOfParts + 1); 			// to make space for text at pos 0

// part variables
var partTotWeight = 0, vWeights, fMessaging, fPartInit, part_nbr = 0, prevPartNbr = 0, partVersion, prevPartVersion = 1, fSendMsg;
var minLen, maxLen, randomLen, partsClock = TempoClock(), tGenerateAuto, tPartsGenerator;
var cancelPart = 0, countup = 0, nextPart = 0, transitionNbr = 0, dispTrans;
var startTime = 0, ending = 0, manualOverrideEnd = 0, firstCountdown = 1;

// control window
var wPartsGenerator, signalColor = Color.green(0.9), tick = 0, coverIndex = nil;
var dispPart, dispPartNext, dispPartnote, bHybridReceive, bHybridSend, dispClock, dispClockCanvas, dispImage, imageObj;
var fReadNotes, fileReadNotes, tmpNote, fileSaveLog, fReadConfig, fileReadConfig, tmpDisabled, partChooser;
var rectWindow, rectStart, rectTest, rectCancelNext, rectClock, rectClockCanvas, rectLoadConfig, rectNotes, rectConfig, rectSetLength, rectRemote, rectMove, rectOSCin, rectOSCout;
var rectPartChooser, rectPartCurrent, rectPartNext, rectPartnote, rectTrans, rectHybridReceive, rectHybridSend, lSetLength, rectSetLengthLabel;
var fontPartCurrent , fontPartNext, fontContraLayer, fontTrans, fontInteract, fontSmall, fontRegular, fontClock, fNewClock, tNewClock;
var bRun, bTest, bLoadConfig, bLoadNotes, bConfigWindow, bCancelNext, nSetLength, bOSCin, bOSCout;
var hybridReceiveEnable = 0, receivingSwToggle = 0, hybridSendEnable = 0;
var screenHeight = Window.screenBounds.height, screenWidth = Window.screenBounds.width;
var rectShowBits, bShowBits, delayBit, randBit, bRemoteClientsOnline, contraLayerNbr;

// config window
var fConfigWindow, wConfig;

// messaging
var fOscResponder;

// cards window
var fShowCard, wCard;

// LapisStatus
var lapisStat;

// OSC listening port
("\nSC is listening to OSC on port:" + NetAddr.langPort).postln;

cfg.put(\countdownOrg, cfg.countdown);

// if length set, always show clock
if(cfg.setLength != 0, {cfg.showClock = 1});

// set hybrid off var
if((cfg.hybridReceiveParts.size==0)&&(cfg.hybridSendParts.size==0),{cfg.hybridOn = 0},{cfg.hybridOn = 1});

// set endPart if nil
if(cfg.endPart.isNil, {cfg.endPart = cfg.nbrOfParts - 1});
("\nEnd part:"+cfg.endPart).postln;

// check validity of project event
"\nValidating project event...".postln;
project.keysDo { |key|
	if(project.at(\name).size != project.at(key).size,
		{("!!! Project event invalid !!! key:" + key).postln})
};

(Document.dir++"Lapis/GlobalVars.scd").load();

// show SauerControl if appropriate
if( ( (cfg.midiSendParts.size>0) || (cfg.midiReceiveParts.size>0) ) && ~wSauerControlAvail.isNil, {
	("SauerControl-"++cfg.project++".scd").loadRelative;
});


///////////////////////////////////////////// functions //////////////////////////////////////

// sending OSC to a NetAddr
fSendMsg = {
	arg netaddr, label, value;
	if(netaddr.notNil, {
		if( (cfg.remoteClientsOnline == 1) || (netaddr.ip == "127.0.0.1"), { netaddr.sendMsg(label, value) });
	});
	// try
	// { netaddr.sendMsg(label, value) }
	// { ("\nNetAddr Error with"+label+value).postln; }
};

// send OSC and update GUI w.r.t. parts
fMessaging =
{
	arg p_mode, p_part_nbr = "", p_count, p_trans_nbr = "", p_notecolor, p_version, p_remote;
	var p_part, p_trans, p_trans_symb;

	if((p_part_nbr != ""), {p_part = partNames[p_part_nbr]});
	if((p_trans_nbr != ""),{
		p_trans = cfg.transitionList[p_trans_nbr];
		p_trans_symb = cfg.transitionSymbolList[p_trans_nbr];
	});

	case
	{p_mode == "next"}
	{
		// remote
		fSendMsg.value(cfg.client1, "/count", p_count);
		fSendMsg.value(cfg.client2, "/count", p_count);
		fSendMsg.value(cfg.client3, "/count", p_count);
		if(p_remote == 1, { // only send to client1 (=Anne) when this flag=1
			fSendMsg.value(cfg.client1, "/part_next",p_part_nbr);
			fSendMsg.value(cfg.client1, "/part_trans",p_trans_nbr);
		});
		fSendMsg.value(cfg.client2, "/part_next",p_part_nbr);
		fSendMsg.value(cfg.client2, "/part_trans",p_trans_nbr);
		fSendMsg.value(cfg.client3, "/part_next",p_part_nbr);
		fSendMsg.value(cfg.client3, "/part_trans",p_trans_nbr);

		// cfg.netaddrTouchOSC.sendMsg("/count", p_count);
		// { cfg.netaddrTouchOSC.sendMsg("/count", p_count) }.defer(0.5);
		// cfg.netaddrTouchOSC.sendMsg("/part_next", p_part);
		// { cfg.netaddrTouchOSC.sendMsg("/part_next", p_part) }.defer(0.5);

		// local
		dispPartNext.states_([[p_part ++ "(" ++ p_count ++ ")"]]).font_(fontPartNext);
		dispTrans.states = [[p_trans_symb]];
		fShowCard.value(p_part_nbr, p_version);
	}

	{p_mode == "new"}
	{
		// remote
		fSendMsg.value(cfg.client1, "/part", p_part_nbr);
		fSendMsg.value(cfg.client2, "/part", p_part_nbr);
		fSendMsg.value(cfg.client3, "/part", p_part_nbr);

		{ // send again just to be sure it arrives
			fSendMsg.value(cfg.client1, "/part", p_part_nbr);
			fSendMsg.value(cfg.client2, "/part", p_part_nbr);
			fSendMsg.value(cfg.client3, "/part", p_part_nbr);
		}.defer(0.5);

		// cfg.netaddrTouchOSC.sendMsg("/count", "");
		// cfg.netaddrTouchOSC.sendMsg("/part_next", p_part);
		// cfg.netaddrTouchOSC.sendMsg("/part_note", "");

		// contrapuntal layer
		if( cfg.contraLayer == 1, {
			contraLayerNbr = rand(cfg.contraLayerList.size);
			fSendMsg.value(cfg.client1, "/contralayer", contraLayerNbr);
			fSendMsg.value(cfg.client2, "/contralayer", contraLayerNbr);
			fSendMsg.value(cfg.client3, "/contralayer", contraLayerNbr);
		});

		// to QC for Shackle Bits
		if(cfg.sendBits == 1, {

			// send immediately
			randBit = rrand(2,cfg.nbrOfParts - 1);
			fSendMsg.value(cfg.client2, "/bit", randBit);
			("\nBit"+randBit+"triggered").postln;

			// send with delay
			if( ([0,1].wchoose([0.5,0.5]) == 0) && (bRun.value == 1), {
				delayBit = rrand(60,90) / cfg.genFactor;
				{
					randBit = rrand(2,cfg.nbrOfParts - 1);
					fSendMsg.value(cfg.client2, "/bit", randBit);
					("\nDelayed bit"+randBit+"triggered").postln;
				}.defer(delayBit);
				("\nDelayed bit trigger by"+delayBit+"sec").postln;
			});
		});

		// local
		dispPart.states = [[p_part]];
		dispTrans.states = [[p_trans_symb]];
		fShowCard.value(p_part_nbr, p_version);
		if( cfg.contraLayer == 1, { dispPartNext.states_([[ cfg.contraLayerList[ contraLayerNbr ] ]]).font_(fontContraLayer) });
	}

	{p_mode == "action"}
	{
		// remote
		fSendMsg.value(cfg.client1, "/part_next", p_part_nbr);
		fSendMsg.value(cfg.client2, "/part_next", p_part_nbr);
		fSendMsg.value(cfg.client3, "/part_next", p_part_nbr);

		// local
		if(p_part_nbr == 0,
			{ dispPartNext.states = [[cfg.textCancel]] },
			{ dispPartNext.states = [[cfg.textNext]] });
		dispPartNext.font_(fontPartNext);
	}

	{p_mode == "clear"}
	{
		// local
		dispPartNext.states = [[""]];
		dispTrans.states = [[""]];
		if(countup != 0, {
			fShowCard.value("clear", "");
		}, {
			if( cfg.contraLayer == 1, { dispPartNext.states_([[ cfg.contraLayerList[ contraLayerNbr ] ]]).font_(fontContraLayer) });
		});
	}

	{p_mode == "note"}
	{
		// cfg.netaddrTouchOSC.sendMsg("/part_note", partNote[part_nbr]);

		// local
		dispPartnote.background_(p_notecolor);
		dispPartnote.string = partNote[part_nbr];
		fShowCard.value(p_part_nbr, p_version);
	}

	{p_mode == "start"}
	{
		// remote
		fSendMsg.value(cfg.client1, "/start",p_part_nbr);
		fSendMsg.value(cfg.client2, "/start",p_part_nbr);
		fSendMsg.value(cfg.client3, "/start",p_part_nbr);

		// local
		dispPart.states = [[""]];
	}
	;

};

// read in config file - details about parts
fReadConfig =
{
	var tmpChances;
	"\nREADING CONFIG...".postln;

	partSpec = Array.newClear(cfg.nbrOfParts);
	partNbrs = Array.new(cfg.nbrOfParts);
	partNames = Array.new(cfg.nbrOfParts);
	partChooserNames = Array.new(cfg.nbrOfParts + 1); // to make space for text in position 0
	partMinLen = Array.new(cfg.nbrOfParts);
	partMaxLen = Array.new(cfg.nbrOfParts);
	partWeight = Array.new(cfg.nbrOfParts);
	partWeight_next = Array.newClear(cfg.nbrOfParts + 1); // +1 for the initial, default weights
	partTotWeightNext = Array.newClear(cfg.nbrOfParts);
	partTotWeight = 0;

	if(File.exists(file.config), {
		fileReadConfig = File(file.config,"r");

		cfg.nbrOfParts.do({ |i|
			partSpec[i] = Array.newClear(5);
			partSpec[i][0] = fileReadConfig.getLine(200); // part name
			partSpec[i][1] = fileReadConfig.getLine(200).asFloat; // min len
			partSpec[i][2] = fileReadConfig.getLine(200).asFloat; // max len
			partSpec[i][3] = fileReadConfig.getLine(200).asFloat; // weight
			tmpDisabled = fileReadConfig.getLine(200); // disabled
			tmpChances = fileReadConfig.getLine(200);  // next weights
			tmpChances = tmpChances.subStr(1,this.size - 1);

			if((tmpDisabled == "1"), {
				partSpec[i][4] = tmpChances.split($,);
				cfg.nbrOfParts.do({ |j|
					// expand chances array with 1's if not big enough
					if( (j >= partSpec[i][4].size),
						{partSpec[i][4].add(1.0)},
						{partSpec[i][4][j] = partSpec[i][4][j].asFloat}
					);
				});
				},
				{partSpec[i][4] = nil}
			);
			fileReadConfig.getLine(200);
		});
		fileReadConfig.close;
		},
		{("\n!!CONFIG" + file.config + "NOT FOUND!!").postln}
	);

	// initialize
	partTotWeightNext.fill(0);
	partChooserNames.add("Parts");

	// populate arrays
	cfg.nbrOfParts.do({
		arg i;
		partNbrs = partNbrs.add(i);
		partNames = partNames.add(partSpec[i][0]);
		if(i >= 2, {partChooserNames = partChooserNames.add(i + ":" + partSpec[i][0]);}); // no CANCEL/NEXT
		partMinLen = partMinLen.add(partSpec[i][1]);
		partMaxLen = partMaxLen.add(partSpec[i][2]);

		// count total weight points
		partTotWeight = partTotWeight + partSpec[i][3];

		// count total weight points 'next'
		if(partSpec[i][4].notNil, {
			cfg.nbrOfParts.do ({
				arg j;
				partTotWeightNext[i] = partTotWeightNext[i] + partSpec[i][4][j];
			});
		});
	});

	// display parameters
	("Part numbers:" + partNbrs).postln;
	("Part Names:  " + partNames).postln;
	("Part min len:" + partMinLen).postln;
	("Part max len:" + partMaxLen).postln;

	// determine weights
	cfg.nbrOfParts.do ({
		arg i;
		partWeight = partWeight.add((partSpec[i][3] / partTotWeight));
		g = 0;

		// determine weights of parts 'next'
		if(partSpec[i][4].notNil,{
			cfg.nbrOfParts.do ({
				arg j;
				partWeight_next[i] =
				partWeight_next[i].add((partSpec[i][4][j] / partTotWeightNext[i]));
			});
			},
			{ partWeight_next[i] = nil; });
		// ("Weights" + partSpec[i][0]+":" + partWeight_next[i]).postln;
		// ("Sum" + partSpec[i][0]+":" + partWeight_next[i].asArray.sum).postln;
	});

	// add initial weights to the end
	partWeight_next[cfg.nbrOfParts] = partWeight;
	("Weights Initial:" + partWeight_next[cfg.nbrOfParts]).postln;
};

// read in notes for parts
fReadNotes = {
	"\nREADING NOTES...".postln;

	if(File.exists(file.notes),{
		fileReadNotes = File(file.notes,"r");
		k = -1;
		partNote = Array.newClear(cfg.nbrOfParts);
		partNote.fill("");

		// keep reading while we still have parts
		while( {k <= (cfg.nbrOfParts - 1)},
			{
				tmpNote = fileReadNotes.getLine(200).asString;
				// starting with * means partnumber & name
				if( (tmpNote.subStr(0,1) == "<*"),
					{ k = k + 1; },
					{
						// starting with +++ means end of file
						if(tmpNote.subStr(0,2) == "+++",
							{ k = cfg.nbrOfParts; },
							{ partNote[k] = partNote[k] + tmpNote + "\n"; });
				});
		});
		fileReadNotes.close;
		},
		{("\n!!NOTES" + file.notes + "NOT FOUND!!").postln});
};

// starting config window to specify part data
fConfigWindow = {
	var configParts = Array.newClear(cfg.nbrOfParts), fileSaveConfig, fileSaveConfigBackup, bSave, bClose;
	var labelPartname, labelMinLength, labelMaxLength, labelExplLength, labelWeight, labelChance, labelDisable, labelLabels, labelLabels2, labels;

	wConfig = Window("Shackle System | Server" + cfg.version + " | Configuration", Rect(20 , 80, 1260, 850), scroll: true)
	.background_(Color.grey(0.9))
	.alwaysOnTop_(true);
	wConfig.front;

	// save button
	bSave = SmoothButton(wConfig, Rect(75, 10, 75, 20))
		.border_(1)
		.radius_(3)
		.font_(Font("Helvetica",10))
		.states_([["SAVE", Color.black, Color.white]])
		.canFocus_(false)
		.action_({
			"\nBACKING UP CONFIG...".postln;
			fileSaveConfig = File.new(file.config,"r");
			fileSaveConfigBackup = File.new(file.configBackup.replace(".txt","")++Date.getDate.stamp++".txt","w");
			fileSaveConfigBackup.write(fileSaveConfig.readAllString);
			fileSaveConfigBackup.close;
			fileSaveConfig.close;

			"\nSAVING CONFIG...".postln;
			fileSaveConfig = File.new(file.config,"w");
			cfg.nbrOfParts.do({|i|
				fileSaveConfig.write(partSpec[i][0]);
				fileSaveConfig.write("\n");
				fileSaveConfig.write(configParts[i].minLen.asString);
				fileSaveConfig.write("\n");
				fileSaveConfig.write(configParts[i].maxLen.asString);
				fileSaveConfig.write("\n");
				fileSaveConfig.write(configParts[i].weight.asString);
				fileSaveConfig.write("\n");
				fileSaveConfig.write(configParts[i].disable.asString);
				fileSaveConfig.write("\n");
				fileSaveConfig.write(configParts[i].chances(cfg.nbrOfParts).asString);
				fileSaveConfig.write("\n");
				fileSaveConfig.write("\n");
			});
			fileSaveConfig.close;
			cfg.nbrOfParts.do({|i|
				configParts[i].saved_();
			});
		});

	// close button
	bClose = SmoothButton(wConfig, Rect(155, 10, 75, 20))
		.border_(1)
		.radius_(3)
		.font_(Font("Helvetica",10))
		.states_([["CLOSE", Color.black, Color.white]])
		.action_({
			wConfig.close();
			fReadConfig.value();
		})
		.canFocus_(false);

	// label row
	labelMinLength = StaticText(wConfig, Rect(75,40,50,20));
	labelMinLength.string = "Min Length";
	labelMinLength.font = Font("Helvetica",9);
	labelExplLength = StaticText(wConfig, Rect(200,40,200,20));
	labelExplLength.string = "(nudge min with shift, max with alt)";
	labelExplLength.font = Font("Helvetica",9);
	labelMaxLength = StaticText(wConfig, Rect(425,40,50,20));
	labelMaxLength.string = "Max Length";
	labelMaxLength.font = Font("Helvetica",9);
	labelWeight = StaticText(wConfig, Rect(480,40,50,20));
	labelWeight.string = "Weight";
	labelWeight.font = Font("Helvetica",9);
	labelChance = StaticText(wConfig, Rect(535,40,200,20));
	labelChance.string = "Chance for other parts after current";
	labelChance.font = Font("Helvetica",9);
	labelDisable = StaticText(wConfig, Rect(540 + (20.5 * cfg.nbrOfParts),40,50,20));
	labelDisable.string = "Disabled";
	labelDisable.font = Font("Helvetica",9);
	labelLabels = StaticText(wConfig, Rect(535,53,600,20));
	labelLabels.font = Font("Helvetica",9);
	labels = "";
	cfg.nbrOfParts.do({ |i|
		labels = labels + partSpec[i][0].subStr(0,2);
	});
	labelLabels.string = labels;
	cfg.nbrOfParts.do({ |i|
		configParts[i] = ShacklePartConfig.new(wConfig, partSpec[i], 0, (70 + (i*35)),cfg.nbrOfParts,cfg.maxLenAbs);
	});
	labelLabels2 = StaticText(wConfig, Rect(535,60 + (cfg.nbrOfParts*35),700,20));
	labelLabels2.font = Font("Helvetica",9);
	labelLabels2.string = labels;
};

// starting and stopping of OSC responders
fOscResponder = {
	// responder to receive next part msg from the other player
	OSCdef(\shackSysNext, { arg message;
		("\nOSC RCV: " ++ message).postln;
		if(cfg.enableRemoteCancelNext==1, {{bCancelNext.valueAction = 0}.defer(0.2)});
	}, cfg.receivingNext).fix;

	// responder to receive the cancel part msg from the other player
	OSCdef(\shackSysCancel, { arg message;
		("\nOSC RCV: " ++ message).postln;
		if(cfg.enableRemoteCancelNext==1, {{bCancelNext.valueAction = 1}.defer(0.2)});
	}, cfg.receivingCancel).fix;

	// responder to receive the cancel/next part msg from the other player
	OSCdef(\shackSysCancelNext, { arg message;
		("\nOSC RCV: " ++ message).postln;
		if(cfg.enableRemoteCancelNext==1, {
			// if counting up in task, cancel part
			if(countup != 0,
				{{bCancelNext.valueAction = 1}.defer(0.2);});
			// if not counting up in task, call next part
			if(countup == 0,
				{{bCancelNext.valueAction = 0}.defer(0.2);})
		});
	}, cfg.receivingCancelNext).fix;

	// responder to receive ctr msg from the other player
	OSCdef(\shackSysCtr, { arg message;
		if(hybridReceiveEnable == 1, {
			//				("\nOSC RCV: " ++ message).postln;

			// switch on if ctr data >= 20
			if((message[1] >= 20) && (receivingSwToggle == 0),
				{
					receivingSwToggle = 1;
					// send OSC data to LiveSampler
					cfg.localAddr.sendMsg("/externalSwitch", receivingSwToggle);
			});

			// switch off if ctr data < 20
			if((message[1] < 20) && (receivingSwToggle == 1),
				{
					receivingSwToggle = 0;
					// send OSC data to LiveSampler
					cfg.localAddr.sendMsg("/externalSwitch", receivingSwToggle);
			});

			// send OSC data to LiveSampler
			if(receivingSwToggle == 1, {cfg.localAddr.sendMsg("/externalController", message[1] / cfg.receivingScale)});
		});
	}, cfg.receivingCtr).fix;

	// responder for Arduino digital sensors
	OSCdef(\shackleSystemArdDig, { |msg|
		("\nOSC RCV ArdDig: " ++ msg).postln;
		case
		{msg[1] == 1 && msg[2] == 1} // switch 1 and only at switchOn
		{
			// if counting up in task, cancel part
			if(countup != 0,
				{{bCancelNext.valueAction = 1}.defer(0.2);});
			// if not counting up in task, call next part
			if(countup == 0,
				{{bCancelNext.valueAction = 0}.defer(0.2);})
		}
		{msg[1] == 2 && msg[2] == 1} // switch 2 and only at switchOn
		{
			if(cfg.sendBits == 1, {
				bShowBits.valueAction_((bShowBits.value+1)%2);
			},
			{
				// if counting up in task, cancel part
				if(countup != 0,
					{{bCancelNext.valueAction = 1}.defer(0.2);});
				// if not counting up in task, call next part
				if(countup == 0,
					{{bCancelNext.valueAction = 0}.defer(0.2);})
			})
		}
		;
	}, "/ard/dig").fix;

	OSCdef(\shackleSystemNoSamplingOn, { |msg|
		"No Sampling Mode ON".postln;
		{ wPartsGenerator.background_(Color.green(0.9)) }.defer();
	}, "/albon").fix;

	OSCdef(\shackleSystemNoSamplingOff, { |msg|
		"No Sampling Mode OFF".postln;
		{ wPartsGenerator.background_(Color.white(0.9)) }.defer();
	}, "/alboff").fix;

	OSCdef(\shackSysHidEx3d, { arg msg;
		var cookie = msg[1];
		var val = msg[2];
		// ("\nOSC RCV Ex3d: " ++ msg).postln;
		if(~oscSrc == "jx", {
			cookie = cookie * 127; 			// back to the MIDI range; this might be f.e. 2 or 2.0001 or 1.9999
			cookie = (cookie + 0.1).floor; 	// make up for rounding errors then make into integer
			// ("Cookie:" + cookie + "Value:" + val).postln;
		});

		// only if hybrid send is enabled
		if(hybridSendEnable == 1, {
			if(cookie == 4, { // button 1
				if(~oscSrc == "jx", {val = 1-val}); // junXion repair
				fSendMsg.value(cfg.client1, cfg.sendingSw, (1 - val));
				// ("\nOSC SND ShackleSystem:" + cfg.sendingSw + (1 - val)).postln;
			});
			if(cookie == 16, {// x-axis
				// junXion repair
				if(~oscSrc == "jx", {val = (1-val) * 1024});
				fSendMsg.value(cfg.client1, cfg.sendingCtr, (1023 - val));
				// ("\nOSC SND ShackleSystem:" + cfg.sendingCtr + (1023 - val)).postln;
			});
		});
	}, "/hid/ex3d").fix;

};

fPartInit = {
	arg p_part_nbr, p_transitionNbr, p_version, close = 0;

	// resetting section
	if(cfg.hybridOn == 1, {
		bHybridReceive.valueAction = 0;
		bHybridSend.valueAction = 0;
	});

	if(midiSendEnabled == 1, { // disable sending MIDI to Sauer organ
		"MIDI send (to Sauer) OFF".postln;
		midiSendEnabled = 0;
		cfg.localAddr.sendMsg("/midiSendEnable", 0);
		});

	if(midiReceiveEnabled == 1, { // disable receiving MIDI from an external source to control SK
		"MIDI receive OFF".postln;
		midiReceiveEnabled = 0;
		cfg.localAddr.sendMsg("/midiReceiveEnable", 0);
		});

	if(close == 0, { // only if not closing window
		// display and send out part info
		{fMessaging.value("new",p_part_nbr,"",p_transitionNbr,"",p_version)}.defer();

		// initializing section
		if(cfg.hybridReceiveParts.includes(p_part_nbr) == true, // hybridReceiveEnable
			{ // enable incoming OSC to send control data to LiveSampler
				bHybridReceive.valueAction = 1;
		});

		if(cfg.hybridSendParts.includes(p_part_nbr) == true, // hybridSendEnable
			{ // enable outgoing HID/OSC to control Nord params plus disable local effect of the interfaces
				bHybridSend.valueAction = 1;
		});

		if(cfg.midiSendParts.includes(p_part_nbr) == true,
			{ // enable sending MIDI to Sauer organ
				"MIDI send (to Sauer) ON".postln;
				midiSendEnabled = 1;
				cfg.localAddr.sendMsg("/midiSendEnable", 1);
			});

		if(cfg.midiReceiveParts.includes(p_part_nbr) == true,
			{ // enable receiving MIDI from an external source to control SK
				"MIDI receive ON".postln;
				midiReceiveEnabled = 1;
				cfg.localAddr.sendMsg("/midiReceiveEnable", 1);
			});

	});
};

fShowCard = {
	arg part, version; // part number
	var cardObj, card;

	if(cfg.showCards == 1, {
		if(part == "clear", {
			card = (cfg.dataDir ++ cfg.project ++ "/Deck/shacklecard-deck-" ++ cfg.cardColor ++".jpg").pathMatch;
			cardObj = Image.new(card[0]);
			wCard.view.backgroundImage_(cardObj);
			},
			{
			//	("\nCard chosen:" + cfg.dataDir ++ cfg.project ++ "/Deck/shacklecard-deck-" ++ part ++ version ++ ".jpg").postln;
			card = (cfg.dataDir ++ cfg.project ++ "/Deck/shacklecard-deck-" ++ part ++ version ++ ".jpg").pathMatch;
			cardObj = Image.new(card[0]);
			wCard.view.backgroundImage_(cardObj);
		});
	});
};

fNewClock = {
	tick = 0;
	inf.do({
		1.wait;
		if( (tick%60) == 0, {
			("\n### "  + (tick/60) + "minutes " ++
				if(cfg.setLength!=0,"(of " ++ (cfg.setLength/60)  ++ ") ", "") ++
				"and counting #######" +
				if(cfg.setLength!=0,"(Alt-E to END)","")).postln;
		});
		// advance
		tick = tick + 1;
		//		{dispClock.string = if(tick>=3600, "  ","   ")++tick.asTimeString}.defer();
		{dispClock.states = [[tick.asTimeStringHM]]}.defer();
		if(cfg.setLength !=0, {
			// if time's up show last part
			if(	(((SystemClock.seconds - startTime) > cfg.setLength) || (manualOverrideEnd == 1))
				&& (ending == 0), {
					"\n### Initiate END #######".postln;
					ending = 1; // set ending to 1 so the last part is proposed
					while(
						{ending == 1},
						{
							{bCancelNext.valueAction = 0}.defer(); // call next part which will be END
							1.wait;
						}
					);
			});
		});
	});
};


///////////////////////////////////////////// tasks //////////////////////////////////////

tPartsGenerator = Task({
	inf.do {
		// check if time's up
		if(ending >= 1, {
			// if time is up choose END part
			part_nbr = partNbrs[cfg.endPart];
			ending = 2; // set ending to 2 to disable any cancel/next action
			{bRun.valueAction = 0}.defer(cfg.countdown + 1); // switch off system
		}, {
			// choose part number
			if((firstCountdown == 1) && (cfg.initialPart > 0), {
				// set partnumber to initial part
				part_nbr = cfg.initialPart;
			}, {
				// check if there are cover tunes to run
				coverIndex = nil;
				cfg.coverTunes.size.do { |i|
					if( (cfg.coverTimes[i] < tick) && (cfg.coverStarted[i]==0), { // this cover tune is up
						part_nbr = cfg.coverTunes[i];
						coverIndex = i;
					});
				};
				if(coverIndex.isNil, { // if no cover tune chosen
					if(cfg.dupAllowed == 0, { // check if duplicates are allowed - if not then ONLY USE GENERIC WEIGHTS
						// choose new partnr randomly excluding the ones already done
						partsTemp = partNbrs.copyRange(2,partNbrs.size - 2);
						partsTemp.takeThese({arg item, index;
							partsDone.includes(item) == true;
							// exclude parts already done
						});
						if(partsTemp.size == 0, { // all parts are done
							partsDone = Array.new(cfg.nbrOfParts);
							partsTemp = partNbrs.copyRange(2,partNbrs.size - 2); // exclude Cancel, Next, End
						});
						("\nParts to choose from:\n" ++ partsTemp).postln;

						// determine weights of parts left to choose from / ONLY GENERIC WEIGHTS
						vWeights = Array.new(cfg.nbrOfParts);
						partsTemp.size.do({|i|
							vWeights.add(partWeight[partsTemp[i]]);
						});
						vWeights = vWeights.normalizeSum;
						("\nWeights - generic:" + vWeights).postln;

						// choose part number using weights
						part_nbr = partsTemp.wchoose(vWeights);
					}, {
						// determine weights
						if(partWeight_next[prevPartNbr].isNil,
							{vWeights = partWeight; ("\nWeights - generic:" + vWeights).postln;},
							{vWeights = partWeight_next[prevPartNbr];
								("\nWeights from prev part" + partNames[prevPartNbr] + ":" + vWeights).postln;});

						// choose new partnr using the weights from prev part
						part_nbr = partNbrs.wchoose(vWeights);
						while({part_nbr == prevPartNbr}, {part_nbr = partNbrs.wchoose(vWeights)});
					});
				});
			});
		});

		// get part name
		("\nProposed Part:" + part_nbr + partNames[part_nbr]).postln;

		// choose transition
		transitionNbr = cfg.transitionList.size.rand;
		("Proposed Transition:" + transitionNbr + cfg.transitionList[transitionNbr]).postln;

		// choose part version
		if(cfg.showCards == 1, {
			partVersion = [1,2,3].choose;
		});

		// display part note in signal color
		{fMessaging.value("note",part_nbr,"","",signalColor)}.defer();

		// announce new part
		while(
			{countup<cfg.countdown && cancelPart == 0}, // jump out if we're cancelling
			{   // this is used for this while loop and to indicate we're counting down
				countup = countup + 1;

				// send OSC out & display next
				{fMessaging.value("next", part_nbr, (cfg.countdown - countup + 1),
					transitionNbr,"", partVersion,
					if(countup <= 5, 1, 0) // only on the first count this is 1
				)}.defer();

				// only if we're not cancelling to make sure we don't whipe out <cancelled>
				if(cancelPart == 0, {0.5.wait});
				if(cancelPart == 0, {{fMessaging.value("clear")}.defer(); });
				if(cancelPart == 0, {0.5.wait});
		});
		countup = 0;

		// set button to 'NEXT'
		{bCancelNext.value = 1}.defer(0.2);

		// arrange prevPartNbr and part_nbr depending on cancel or not
		if((cancelPart == 0), { // no cancel
			if(coverIndex.notNil, {cfg.coverStarted[coverIndex] = 1}); // if this is a cover tune, mark it as started
			if(cfg.dupAllowed == 0, { // add part to the list of parts done
				partsDone.add(part_nbr);
				("\nParts already done:\n" ++ partsDone).postln;
			});

			// store prev part number
			prevPartNbr = part_nbr;
			prevPartVersion = partVersion;
			("\nAccepted Part:" + part_nbr + partNames[part_nbr]).postln;

			// keep track of first cancel
			if(firstCountdown == 1, {firstCountdown = 0; "\nGenerator: just finished first countdown".postln;});

			// initialize new part, incl sending out OSC
			{fPartInit.value(part_nbr, transitionNbr, partVersion)}.defer();
		}, {
			// if cancelling restore original part
			part_nbr = prevPartNbr;
			partVersion = prevPartVersion;
			("\nPrevious Part after Cancel:" + part_nbr + partNames[part_nbr]).postln;

			// if cancelled part is a cover tune, reschedule
			if(coverIndex.notNil, {cfg.coverTimes[coverIndex] = cfg.coverTimes[coverIndex] + cfg.coverReschedule});

			// log cancellation
			fileSaveLog.write(Date.getDate.asString + "<cancelled>\n");

			// if cancelled and first countdown, force next
			if(firstCountdown == 1, {{bCancelNext.valueAction_(0)}.defer()});
		});

		// display part note - after cancel this will reset the old note and card
		if(firstCountdown == 0, {
			{fMessaging.value("note",part_nbr,0,"",Color.white, partVersion)}.defer();
		});

		// determine random wait
		minLen = partMinLen[part_nbr] / cfg.genFactor;
		maxLen = partMaxLen[part_nbr] / cfg.genFactor;
		randomLen = rrand(minLen,maxLen);

		// if cancelled and not the first cancel, divide length by factor
		if((cancelPart != 0) && (firstCountdown==0),{
			("\nLength before cancel factor:" + randomLen.round(1e-1) + "sec").postln;
			randomLen = randomLen / cfg.cancelFactor;
		}, {"".postln});
		("Length:" + randomLen.round(1e-1) + "sec").postln;

		// round to whole numbers
		randomLen = randomLen.round(1);

		// log choice
		fileSaveLog.write(Date.getDate.asString + "TICK" + tick.asTimeStringHM + "Part" + partNames[part_nbr] +
			"with length" + (randomLen + cfg.countdown).asString + "sec and transition" + cfg.transitionList[transitionNbr]  + "\n");

		// count up - waiting for next loop
		i = 0;
		while(
			{i<randomLen && nextPart == 0},
			{if(cfg.showCount == 1, {(randomLen - i).postln}); 1.wait; i = i + 1;});

		// set button to 'CANCEL'
		{bCancelNext.value = 0}.defer(0.2);

		// log next part
		if(nextPart == 1, {fileSaveLog.write(Date.getDate.asString + "<nextPart>\n")});
	};
},
partsClock);

// to run the generator automatically
tGenerateAuto = Task {
	inf.do {
		"\n---> AutoRun Generator running".postln;
		if(countup == 0,{{bCancelNext.valueAction = 0}.defer(0.2);});
		(cfg.countdown + 6).wait;
	};
};


///////////////////////////////////////////// read config data  //////////////////////////////////////

fReadConfig.value();
fReadNotes.value();

///////////////////////////////////////////// status window //////////////////////////////////////

// window layout
rectMove = -20;
rectWindow = Rect(280, (screenHeight - (600 + (2*cfg.winAdd))), 480 + (2*cfg.winAdd), 385 + rectMove + (2*cfg.winAdd));
rectPartCurrent = Rect(5 +  cfg.winAdd, 5 +  cfg.winAdd, 205, 40);
rectTrans = Rect(215 +  cfg.winAdd, 5 +  cfg.winAdd, 50, 40);
rectPartNext = Rect(270 +  cfg.winAdd, 5 +  cfg.winAdd, 205, 40);
rectPartnote = Rect(5 +  cfg.winAdd, 50 +  cfg.winAdd, 470, 160 + rectMove);
rectCancelNext = Rect(5 +  cfg.winAdd, 213 + rectMove + cfg.winAdd,
	370 + ((1-cfg.sendBits)*(1-cfg.onLine)*50) - (cfg.showClock*138) - (cfg.hybridOn*50), 70);
rectClock = Rect(242 +  cfg.winAdd + ((1-cfg.sendBits)*(1-cfg.onLine)*50) - (cfg.hybridOn*50), 213 + rectMove + cfg.winAdd, 132, 70);
rectClockCanvas = Rect(242 +  cfg.winAdd + ((1-cfg.sendBits)*(1-cfg.onLine)*50) - (cfg.hybridOn*50), 213 + rectMove + cfg.winAdd, 132, 70);
rectShowBits = Rect(380 +  cfg.winAdd - (cfg.hybridOn*50),  213 + rectMove + cfg.winAdd, 45, 32);
rectRemote = Rect(380 +  cfg.winAdd  - (cfg.hybridOn*50), 251 + rectMove + cfg.winAdd, 45, 32);
rectHybridReceive = Rect(380 +  cfg.winAdd, 213 + rectMove + cfg.winAdd, 45, 32);
rectHybridSend = Rect(380 +  cfg.winAdd, 251 + rectMove + cfg.winAdd, 45, 32);
rectStart = Rect(430 +  cfg.winAdd, 213 + rectMove + cfg.winAdd, 45, 32);
rectTest = Rect(430 +  cfg.winAdd, 251 + rectMove + cfg.winAdd, 45, 32);
rectLoadConfig = Rect(5 +  cfg.winAdd, 360 + rectMove + cfg.winAdd, 75, 20);
rectNotes = Rect(85 +  cfg.winAdd, 360 + rectMove + cfg.winAdd, 75, 20);
rectConfig = Rect(165 +  cfg.winAdd, 360 + rectMove + cfg.winAdd, 75, 20);
rectSetLengthLabel = Rect(265 +  cfg.winAdd, 360 + rectMove + cfg.winAdd, 100, 20);
rectSetLength = Rect(299 +  cfg.winAdd, 360 + rectMove + cfg.winAdd, 30, 20);
rectPartChooser = Rect(380 +  cfg.winAdd,360 + rectMove + cfg.winAdd,95,20);
rectOSCin = Rect(5 +  cfg.winAdd, 330 + rectMove + cfg.winAdd, 75, 20);
rectOSCout = Rect(85 +  cfg.winAdd, 330 + rectMove + cfg.winAdd, 75, 20);

fontPartCurrent = Font("Helvetica",30, true);
fontTrans = Font("Helvetica",30, true);
fontPartNext = Font("Helvetica",30, true);
fontContraLayer = Font("Helvetica",25, false, true);
fontInteract = Font("Helvetica",30, true);
fontClock = Font("Helvetica",30, true);
fontSmall =  Font("Helvetica",10);
fontRegular =  Font("Helvetica",10);

// define window
wPartsGenerator = (Window("Shackle System | Server" + cfg.version + "|" + cfg.project, rectWindow, resizable: true)
	.background_(Color.white(0.9))
);

// part displays
dispPart = (SmoothButton(wPartsGenerator, rectPartCurrent)
	.border_(1).radius_(3).canFocus_(false)
	.font_(fontPartCurrent).background_(Color.white).states_([["..."]])
);
dispPartNext = (SmoothButton(wPartsGenerator, rectPartNext)
	.border_(1).radius_(3).canFocus_(false)
	.font_(fontPartNext).background_(Color.white).states_([["..."]])
);
dispPartnote = (StaticText(wPartsGenerator, rectPartnote)
	.align_(\topLeft).canFocus_(false).background_(Color.white).font_(cfg.fontPartnote)
);
dispTrans = (SmoothButton(wPartsGenerator, rectTrans)
	.border_(1).radius_(3).canFocus_(false)
	.font_(fontTrans).background_(Color.white).states_([["..."]])
);

// cancel / next button
bCancelNext = (SmoothButton(wPartsGenerator, rectCancelNext)
	.border_(1).radius_(3).font_ (fontInteract).canFocus_(false)
	.states_([["CANCEL", Color.black, Color.white],["NEXT", Color.black, Color.white]])
	.action_({
		if(ending != 2, { // if ending = 2, don't alllow cancel/next
			if(bCancelNext.value == 1, { // cancel part
				nextPart = 0;
				cancelPart = 1;
				{fMessaging.value("action",0)}.defer();
				AppClock.sched(2,{cancelPart = 0; fMessaging.value("clear"); nil});
			},{ // next part
				cancelPart = 0;
				nextPart = 1;
				{fMessaging.value("action",1)}.defer();
				AppClock.sched(2,{nextPart = 0; nil});
			});
		});
	})
);

// clock
if(cfg.showClock == 1, {
	dispClock = (SmoothButton(wPartsGenerator, rectClock)
		.border_(1).radius_(3).canFocus_(false)
		.font_(fontClock).background_(Color.white).states_([["00:00"]])
	);
});

// bits button
if(cfg.sendBits == 1, {
	bShowBits = (SmoothButton(wPartsGenerator, rectShowBits)
		.border_(1).radius_(3)
		.canFocus_(false).font_ (fontRegular)
		.states_([["BITS", Color.black, Color.white],["BITS", Color.black, signalColor]])
		.action_({
			fSendMsg.value(cfg.client2, "/bit_alpha",bShowBits.value);
			{fSendMsg.value(cfg.client2, "/bit_enable",bShowBits.value)}.defer(0.1);
			(if(bShowBits.value==0, {"\nDisabling"}, {"\nEnabling"}) + "Bits display").postln;
		})
	);
});

// switch for cfg.remoteClientsOnline
if(cfg.onLine == 1, {
	bRemoteClientsOnline = (SmoothButton(wPartsGenerator, rectRemote)
		.border_(1).radius_(3).canFocus_(false)
		.states_([["OFFLINE", Color.black, Color.white],["ONLINE", Color.black, signalColor]])
		.font_(fontSmall).value_(cfg.remoteClientsOnline)
		.action_({
			cfg.remoteClientsOnline = (cfg.remoteClientsOnline+1)%2;
			("\nSwitching remote clients" + if(cfg.remoteClientsOnline==1, {"ONLINE"}, {"OFFLINE"})).postln;
		})
	);
});

// external send/receive buttons
if(cfg.hybridOn == 1, {
	bHybridReceive = (SmoothButton(wPartsGenerator, rectHybridReceive)
		.border_(1).radius_(3).canFocus_(false).font_ (fontRegular)
		.states_([["RCV", Color.black, Color.white],["RCV", Color.black, signalColor]])
		.action_({
			if(bHybridReceive.value == 1, {
				"\nEnable receive".postln;
				hybridReceiveEnable = 1;
			},{
				"\nDisable receive".postln;
				hybridReceiveEnable = 0;
				// enable local control in LiveSampler
				receivingSwToggle = 0;
				cfg.localAddr.sendMsg("/externalSwitch", receivingSwToggle);
			});
		})
	);
	bHybridSend = (SmoothButton(wPartsGenerator, rectHybridSend)
		.border_(1).radius_(3).canFocus_(false).font_ (fontRegular)
		.states_([["SND", Color.black, Color.white],["SND", Color.black, signalColor]])
		.action_({
			if(bHybridSend.value == 1, {
				"\nEnable send".postln;
				hybridSendEnable = 1;
			},{
				"\nDisable send".postln;
				hybridSendEnable = 0;
			});
			// let LiveSampler know so it can enable/disable button1
			cfg.localAddr.sendMsg("/button1disable", hybridSendEnable);
		})
	);
});

// start and stop parts generator
bRun = (SmoothButton(wPartsGenerator, rectStart)
	.border_(1).radius_(3).canFocus_(false).font_ (fontRegular)
	.states_([["RUN", Color.black, Color.white],["STOP", Color.white, Color.black]])
	.action_({
		if(bRun.value == 1, { // START
			partChooser.value_(0); // set part chooser to 0
			partChooser.enabled_(false);
			countup = 0;  // reset countup in case we stopped during countup
			cancelPart = 0; // reset cancel flag in case we stopped during cancellation
			if((prevPartNbr == 0) || (prevPartNbr == (cfg.nbrOfParts - 1)), { // if no prev part or End, reset for initial weights
				prevPartNbr = if(cfg.initialPart == 0, {rrand(2,cfg.nbrOfParts-2)},{cfg.initialPart});
				fPartInit.value(prevPartNbr,0,1);
				dispPartnote.string = partNote[prevPartNbr];
			});
			fMessaging.value("start",1);
			firstCountdown = 1;
			if(cfg.showClock == 1, {
				startTime = SystemClock.seconds;
				manualOverrideEnd = 0;
				ending = 0;
				dispClock.states = [["00:00"]];
				tNewClock = Task(fNewClock).play;
			});
			if(cfg.dupAllowed == 0, {
				partsDone = Array.new(cfg.nbrOfParts); // reset array containing parts already done
				//			partsDone.add(prevPartNbr); // add initial part to 'already done'
			});
			tPartsGenerator.start;
			fileSaveLog = File(file.log, "a"); // open logfile
			fileSaveLog.write("\n" ++ Date.getDate.asString + "Generator started\n");
		},{ // STOP
			tPartsGenerator.stop;
			fileSaveLog.write(Date.getDate.asString + "Generator stopped\n");
			fileSaveLog.close; // close logfile
			if(cfg.showClock == 1, {tNewClock.stop});
			fMessaging.value("start",0);
			partsClock.clear; // clear tasks
			dispPartnote.background_(Color.white);
			bCancelNext.value= 0; // reset next/cancel button to cancel
			dispPartNext.states = [["..."]];
			partChooser.enabled_(true);
			partChooser.focus;
			partChooser.valueAction_(prevPartNbr - 1); // activate current part
			fShowCard.value(prevPartNbr, prevPartVersion);
		});
	})
);

// test mode
bTest = (SmoothButton(wPartsGenerator, rectTest)
	.border_(1).radius_(3).canFocus_(false).font_ (fontRegular)
	.states_([["TEST", Color.black, Color.white],["TEST", Color.white, Color.black]])
	.action_({
		if(bTest.value == 1,
			{cfg.countdown = 5;  cfg.genFactor = 10},
			{cfg.countdown = cfg.countdownOrg;  cfg.genFactor = 1});
	})
);

// OSC monitor
bOSCin = (SmoothButton(wPartsGenerator, rectOSCin)
	.border_(1).radius_(3).font_(fontRegular).canFocus_(false)
	.states_([ ["OSC in"], ["OSC in",Color.black, Color.green] ])
	.action_({ |b|
		if(b.value==1,
			{ thisProcess.oscInMonitor(true, addr:1, excl: ['/InBus','/hid/ex3d', '/ard/ana', '/midi/control']) },
			{ thisProcess.oscInMonitor(false) });
	})
);
bOSCout = (SmoothButton(wPartsGenerator, rectOSCout)
	.border_(1).radius_(3).font_(fontRegular).canFocus_(false)
	.states_([ ["OSC out"], ["OSC out",Color.black, Color.green] ])
	.action_({ |b|
		if(b.value==1, { ~oscOutMonitor = 1 }, { ~oscOutMonitor = 0 } )
	})
);

// load config file
bLoadConfig = (SmoothButton(wPartsGenerator, rectLoadConfig)
	.border_(1).radius_(3).canFocus_(false).font_ (fontSmall)
	.states_([["Load config", Color.black, Color.white]])
	.action_({ fReadConfig.value() })
);

// load notes file
bLoadNotes = (SmoothButton(wPartsGenerator, rectNotes)
	.border_(1).radius_(3).canFocus_(false).font_ (fontSmall)
	.states_([["Load notes", Color.black, Color.white]])
	.action_({ fReadNotes.value() })
);

// run config window
bConfigWindow = (SmoothButton(wPartsGenerator, rectConfig)
	.border_(1).radius_(3).canFocus_(false).font_ (fontSmall)
	.states_([["Config", Color.black, Color.white]])
	.action_({ fConfigWindow.value() })
);

// setLength label and numberbox
if(cfg.showClock == 1, {
	lSetLength = (StaticText(wPartsGenerator, rectSetLengthLabel)
		.string_("Length              min.")
		.font_(fontSmall)
	);
	nSetLength = (SmoothNumberBox(wPartsGenerator, rectSetLength)
		.radius_(2).border_(1).align_(\center).font_(fontSmall)
		.clipLo_(0).clipHi_(180).value_(cfg.setLength / 60).allowedChars_("1234567890")
		.action_({
			cfg.setLength = nSetLength.value * 60;
			("\nSet length:"+(cfg.setLength/60)+" minutes").postln;
		});
	);
});

// part notes edit
partChooser = (PopUpMenu(wPartsGenerator, rectPartChooser)
	.canFocus_(true).items_(partChooserNames).background_(signalColor).font_ (fontSmall)
	.action_({
		if(partChooser.value != 0, {
			prevPartNbr = partChooser.value + 1;
			fPartInit.value(prevPartNbr,0,1);
			dispPartnote.string = partNote[prevPartNbr];
		},{
			dispPartnote.string = "";
			//			dispPart.value = "";
			dispPart.states = [[""]];
		});
	})
	.keyDownAction_({
		arg view, char, modifiers, unicode, keycode;
		// page down -> next part
		if((keycode == 125 && partChooser.enabled), {
			if(partChooser.value == (partChooserNames.size-1), {
				partChooser.valueAction_(0)
				},{
					partChooser.valueAction_(partChooser.value + 1)
			});
		});
		// page up -> prev part
		if((keycode == 126 && partChooser.enabled),{
			if(partChooser.value == 0, {
				partChooser.valueAction_(partChooserNames.size-1)
				},{
					partChooser.valueAction_(partChooser.value - 1)
			});
		});
		false
}));

// track spacebar press
wPartsGenerator.view.keyDownAction_({
	arg view, char, modifiers, unicode, keycode;
	// [keycode, modifiers].postln;
	// if spacebar pressed and counting up in task, cancel part
	if(((keycode == 49) && (countup != 0)),
		{{bCancelNext.valueAction = 1}.defer(0.2);});
	// if spacebar is pressed and we're not counting up in task, call next part
	if(((keycode == 49) && (countup == 0)),
		{{bCancelNext.valueAction = 0}.defer(0.2);});
	// letter g -> start to run generator automatically
	if((keycode == 5) && (modifiers.isAlt),
		{ if(tGenerateAuto.isPlaying,
			{tGenerateAuto.stop; "\nStop AutoRun Generator".postln},
			{tGenerateAuto.start; "\nStart AutoRun Generator".postln});
	});
	// key f -> fullscreen
	if((keycode == 3) && (modifiers == 0),{
		if(wPartsGenerator.fullScreen==0, {
			wPartsGenerator.fullScreen
		}, {
			wPartsGenerator.endFullScreen
		});
	});
	// alt-o -> switch cfg.remoteClientsOnline
	if((keycode == 31) && (modifiers.isAlt) && (cfg.onLine == 1), { bRemoteClientsOnline.valueAction_((bRemoteClientsOnline.value+1)%2) });
	// alt-b -> switch Bits button on/off
	if((keycode == 11) && (modifiers.isAlt) && (cfg.sendBits == 1), { bShowBits.valueAction_((bShowBits.value+1)%2) });
	// alt-e -> manual override to go to END
	if((keycode == 14) && (modifiers.isAlt) && (cfg.setLength !=0),
		{manualOverrideEnd = 1; "\n###  Manual Override #######".postln});
	// alt-i -> set current part as initial part
	if((keycode == 34) && (modifiers.isAlt), {
		cfg.initialPart = prevPartNbr;
		("Initial part set to" + cfg.initialPart).postln;
	});
});

wPartsGenerator.front;
wPartsGenerator.onClose_({
	fPartInit.value(cfg.nbrOfParts - 1, close: 1); // select 'END' so things get reset
	tPartsGenerator.stop;
	tGenerateAuto.stop;
	if(cfg.showClock == 1, {tNewClock.stop});
	if(notNil(wConfig), {wConfig.close()});
	if(notNil(fileSaveLog), {fileSaveLog.close});
	OSCdef(\shackSysNext).free; OSCdef(\shackSysCancel).free; OSCdef(\shackSysCancelNext).free; OSCdef(\shackSysCtr).free;
	OSCdef(\shackSysHidEx3d).free;
	OSCdef(\shackleSystemArdDig).free; OSCdef(\shackleSystemNoSamplingOn).free; OSCdef(\shackleSystemNoSamplingOff).free;
	wCard.close;
	if(cfg.client1.notNil, {cfg.client1.disconnect});
	if(cfg.client2.notNil, {cfg.client2.disconnect});
	if(cfg.client3.notNil, {cfg.client3.disconnect});
	cfg.localAddr.disconnect;
	lapisStat.stop;
	if(~wSauerControlAvail.notNil, {~wSauerControl.close});
});

// cards window
wCard = Window("Card", Rect(700, 100, 355, 638));
wCard.view.background_(Color.white);
if(cfg.showCards == 1, {wCard.front;});

// include LapisStatus GUI
lapisStat = LapisStatus.new(5+cfg.winAdd,270+cfg.winAdd,25, wPartsGenerator);

// initializing bits
if(cfg.sendBits == 1, {
	fSendMsg.value(cfg.client2, "/bit_alpha",0);
	{fSendMsg.value(cfg.client2, "/bit_enable",0)}.defer(0.1);
});


///////////////////////////////////////////// initialize  //////////////////////////////////////

fOscResponder.value();

// choose initial part
partChooser.valueAction_(
	if(cfg.initialPart == 0, {rrand(2,cfg.nbrOfParts-2)},{cfg.initialPart})
	- 1);
partChooser.focus;
)




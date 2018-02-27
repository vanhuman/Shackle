/*
Curves project 2016

## Channel mapping

main:   Anne 1 -- AnneEfx 4
alt:       Sven 3 -- Matthias 2

Set 1
	\audioStrip, "drums dub delay, dec (rate ctl), resample",
	\audioRing, "blue11zone2+high, dynrec M+A, FFTsynth",
	\tunnel, "blue3-1&8 zone2&4, rev bankB-1, green3-11",
	\fotoPerlSteady, "blue2-5 & blue3-12, dynrec M+A, pitchFol+dec on M",
	\fotoPerlRotated, "green11nasty hits, dec, slapback -> static, resample",

Set 2
	\envirBlend, "droning on C, alternate LV1-2&4 plus 3, efxBankB-1",
	\audioStrip, "drums dub delay, dec (rate ctl), resample",
	\audioPlane, "green2-7",
	\fotoPerlNonSteady, "---",
	\circOrbit, "---"
	\envirBlend, "droning on C, alternate LV1-2&4 plus 3, efxBankB-1",
	\audioRing, "blue11zone2+high, dynrec M+A, FFTsynth",
	\audioFluid, "green1-3 dry",

*/

(

///////////////////////////////////////////// variables //////////////////////////////////////

var imageCtrlOnline = 0, imageSendCtrlActive = 0, imageCtrlAddr = NetAddrMon("169.254.0.9", 7777);
var anneOnline = 0, anneAddr = NetAddrMon("169.254.0.1", 57121);
var countDownEnabled = 1, countNbr = 10; // enable countdown of countNbr steps
var delayInChannel = 1; // input hardware channel for delay effect

var valX = 0, valY = 0, valR = 0, sceneAppClock, writeData = 0, readData = 0;
var fReadDataLoop, fReadData, tReadData, fWriteData, taskCountDown, fDelay, fCurvesOSC, tCurves;
var localAddr = NetAddr("127.0.0.1", 57120);
var wCurves, bFFTpack, sFFTpack, bOSCin, bOSCout, bDelay, sDelay, sFreqRange, bImageCtrlSend, tScene, bWrite, bRead, tCountDown;
var volDelayBus = Bus.control(s,1).set(0), volFFTBus = Bus.control(s,1).set(5), freqRangeBus = Bus.control(s,1).set(0.5);
var synthDelay = nil, synthFFTpack = nil, lapisStat;
var spec = (
	distFftDrone: Env.new([10,1],[1]),
	cutoffFftDrone: Env.new([10000,1000,500],[0.5,0.5],[\lin]),
	pulseFftDrone: Env.new([1,0.3,1],[0.5,0.5]),
	amp: Env.new([0,5,20],[0.5,0.5]),
	freqRange: Env.new([500,5000],[1])
);
var oscMsgOffset = 2, grid = 10, sceneIndex, sceneCount = 0, fileWrite;
var scenes = [
	\audioStrip, "drums dub delay, dec (rate ctl), resample",
	\audioRing, "blue11zone2+high, dynrec M+A, FFTsynth",
	\tunnel, "blue3-1&8 zone2&4, rev bankB-1, green3-11",
	\fotoPerlSteady, "blue2-5 & blue3-12, dynrec M+A, pitchFol+dec on M",
	\fotoPerlRotated, "green11nasty hits, dec, slapback -> static, resample",
	\envirBlend, "droning on C, alternate LV1-2&4 plus 3, efxBankB-1",
	\fotoPerlNonSteady, "---",
	\audioPlane, "green2-7",
	\audioFluid, "green1-3 dry",
	\circOrbit, "---"
];
var sceneVideoControl = ["_V", "_V", "_V", "", "", "", "", "", "", ""];

// load global variables
(Document.dir++"Lapis/GlobalVars.scd").load();


///////////////////////////////////////////// synthdefs //////////////////////////////////////

SynthDef(\fftPack, {
	arg gate = 1, freqRangeBus, volFFTBus;
	var mags = NamedControl.kr(\mags, 0.01 ! (grid*grid));
	var hues = NamedControl.kr(\hues, 0.01 ! (grid*grid));
	var sig, env, freqs, gain = 0.2, freqRangeVal = 1;

	env = EnvGen.kr(Env.adsr(2,0,1,4), gate, doneAction:2);
	freqRangeVal = IEnvGen.kr(spec.freqRange, In.kr(freqRangeBus,1));

	// FULL version
	// freqs = Array.series(grid*grid, 0, 1/(grid*grid));
	// freqs = freqs.linexp(0,1, 50, (hues * LFNoise1.kr(0.1).range(500,freqRangeVal)));
	// sig = Splay.ar(SinOsc.ar(freqs, mul: mags));

	// GRID version
	sig = Array.fill(grid, {|y|
		Array.fill(grid, {|x|
			SinOsc.ar(
				(x / grid).linexp(0, 1, 50, (hues[y * grid + x] * LFNoise1.kr(0.1).range(500,freqRangeVal))),
			mul: mags[y * grid + x]);
		});
	});
	sig = Splay.ar(sig.flat);

	sig = gain * In.kr(volFFTBus,1) * env * sig;
	Out.ar(~aBus.outMain, sig);
}).add;

SynthDef(\curvesDelay, {
	arg volDelayBus, gate = 1;
	var sig, env;

	env = EnvGen.kr( Env.asr, gate, doneAction: 2);
	sig = SoundIn.ar([delayInChannel,delayInChannel]) * (9.dbamp);

	sig[0] = AllpassC.ar(sig[0], 10,
		LFNoise0.ar(LFNoise0.ar(8).range(0.5,10)).range(0.03,0.4),
		LFNoise0.ar(0.3).range(1,12)
	);
	sig[1] = AllpassC.ar(sig[1], 10,
		LFNoise0.ar(LFNoise0.ar(10).range(0.5,10)).range(0.01,0.2),
		LFNoise0.ar(0.5).range(0.5,10)
	);

	Out.ar(~aBus.outMain, 0.2 * sig * env * In.kr(volDelayBus,1));
}).add;


///////////////////////////////////////////// data acquisition //////////////////////////////////////

// image data ---------------------------

OSCdef(\mags, { |msg|
	if(synthFFTpack.notNil, {
		synthFFTpack.set('mags', msg.copyRange(oscMsgOffset, (grid*grid) + oscMsgOffset));
	});
	if(writeData==1, {fileWrite.write(msg.asCompileString+"\n")});
},"/mags").fix;

OSCdef(\hues, { |msg|
	if(synthFFTpack.notNil, {
		synthFFTpack.set('hues', msg.copyRange(oscMsgOffset, (grid*grid) + oscMsgOffset));
	});
	if(writeData==1, {fileWrite.write(msg.asCompileString+"\n")});
},"/hues").fix;

OSCdef(\transition, { |msg|
	msg.postln;
	sceneIndex = scenes.indexOf(msg[1]);
	// send OSC
	if(anneOnline == 1, {
		anneAddr.sendMsg("/scene", msg[1].asString ++ sceneVideoControl[sceneIndex/2]);
		("Scene:"+msg[1]+sceneVideoControl[sceneIndex/2]+"sent to Anne").postln;
	});
	// local display
	if(sceneIndex.notNil, {
		sceneAppClock.clear;
		{ tScene.string = scenes[sceneIndex].asString ++ "\n" ++ scenes[sceneIndex+1] + sceneVideoControl[sceneIndex/2] }.defer;
		{ tScene.stringColor = Color.blue }.defer; sceneAppClock = AppClock.sched(countNbr, { tScene.stringColor = Color.black });
	});
	// countdown
	taskCountDown.stop;
	if( (countDownEnabled == 1) && (msg[2].isNil), {
		{ tCountDown.background = Color.green }.defer;
		taskCountDown = Task({
			countNbr.do { arg count;
				if(anneOnline == 1, {
					anneAddr.sendMsg("/scene", msg[1].asString ++ sceneVideoControl[sceneIndex/2]);
					anneAddr.sendMsg("/count", 9 - count);
				});
				{ tCountDown.string = 9 - count }.defer;
				// (9 - count).postln;
				1.wait;
			};
			{ tCountDown.string = "" }.defer;
			{ tCountDown.background = Color.white }.defer;
		}).start;
	});

},"/transition").fix;

// local controllers ---------------------------

OSCdef(\curvesEx3d, { |msg|
	var cookie = msg[1], val = msg[2];
	// [cookie, val].postln;
	if(imageCtrlOnline==1, { case { cookie==16 } { valX = val/1024 } { cookie==17 } { valY = val/1024 } { cookie==19 } { valR = val/255 }; });
}, "/hid/ex3d").fix;

OSCdef(\curvesNON, { |msg|
	var chan, note, vel, src;
	chan = msg[1]; note = msg[2]; vel = msg[3]; src = msg[4].asString;
	// [chan,note,vel, src].postln;
	if(src == "MUL", { // MIDI Channel 1: LX red buttons keyset 1 & 2 Record & Config
		if( (chan==0) && (note == 12), { // switch on resynthesis
			bFFTpack.valueAction_(1);
			"Curves: resynthesis ON".postln;
		});
		if( (chan==0) && (note == 13), { // switch on Curves image control, so OSC is send out in Controllers.scd
			bImageCtrlSend.valueAction_(1);
			"Curves: Image Control ON".postln;
		});
	});
}, "/midi/noteOn").fix;

OSCdef(\curvesNOF, { |msg|
	var chan, note, vel, src;
	chan = msg[1]; note = msg[2]; vel = msg[3]; src = msg[4].asString;
	//	[chan,note,vel, src].postln;
	if(src == "MUL", { // MIDI Channel 1: LX red buttons keyset 1 Record & Config
		if( (chan==0) && (note == 12), { // switch off resynthesis
			bFFTpack.valueAction_(0);
			"Curves: resynthesis OFF".postln;
		});
		if( (chan==0) && (note == 13), { // switch off Curves image control, so OSC is not send out in Controllers.scd
			bImageCtrlSend.valueAction_(0);
			"Curves: Curves Image Control OFF".postln;
		});
	});
}, "/midi/noteOff").fix;


// remote controllers ---------------------------

OSCdef(\Slider1, { |msg|
	// msg.postln;
	{ sDelay.valueAction_(msg[1]) }.defer;
}, "/1/fader1").fix;
// }, "/Slider1").fix;

OSCdef(\Slider2, { |msg|
	// msg.postln;
	if(imageCtrlOnline==1, {
		imageCtrlAddr.sendMsg(
			"/nodePar", 9,
			3, "audioStrip", "aux2", msg[1],
			3, "audioRing", "aux2", msg[1],
			3, "audioTunnel", "aux2", msg[1],
			3, "fotoPerl", "aux2", msg[1],
			3, "fotoPerl", "aux2", msg[1],
			3, "envirBlend", "aux2", msg[1],
			3, "fotoPerl", "aux2", msg[1],
			3, "audioPlain", "aux2", msg[1],
			3, "audioFluid", "aux2", msg[1]
		);
	});
}, "/Slider2").fix;

OSCdef(\Slider3, { |msg|
	// msg.postln;
	if(imageCtrlOnline==1, {
		imageCtrlAddr.sendMsg(
			"/nodePar", 9,
			3, "audioStrip", "aux3", msg[1],
			3, "audioRing", "aux3", msg[1],
			3, "audioTunnel", "aux3", msg[1],
			3, "fotoPerl", "aux3", msg[1],
			3, "fotoPerl", "aux3", msg[1],
			3, "envirBlend", "aux3", msg[1],
			3, "fotoPerl", "aux3", msg[1],
			3, "audioPlain", "aux3", msg[1],
			3, "audioFluid", "aux3", msg[1]
		);
	});
}, "/Slider3").fix;

OSCdef(\Button1, { |msg|
	// msg.postln;
	fDelay.value(msg[1]);
	bDelay.value_(msg[1]);
}, "/1/toggle1").fix;
// }, "/Button1").fix;

OSCdef(\Button2, { |msg|
	// msg.postln;
}, "/Button2").fix;

OSCdef(\Button3, { |msg|
	// msg.postln;
}, "/Button3").fix;


///////////////////////////////////////////// functions //////////////////////////////////////

fCurvesOSC = {
	inf.do {
		if(imageSendCtrlActive==1, { // only if sending engaged (red1 keyset2 / set in LiveSampler)
			// values to send: valX, valY, valR, all 0-1
			imageCtrlAddr.sendMsg(
				"/nodePar", 9,
				3, "audioStrip", "aux1", valX,
				3, "audioRing", "aux1", valX,
				3, "audioTunnel", "aux1", valX,
				3, "fotoPerl", "aux1", valX,
				3, "fotoPerl", "aux1", valX,
				3, "envirBlend", "aux1", valX,
				3, "fotoPerl", "aux1", valX,
				3, "audioPlain", "aux1", valX,
				3, "audioFluid", "aux1", valX
			);
		});
		(1/60).wait;
	};
};

fDelay = {
	arg value;
	if( value==1,
		{ if(synthDelay.isNil, { synthDelay = Synth(\curvesDelay, [\volDelayBus, volDelayBus.index] ) }) },
		{ synthDelay.release; synthDelay = nil }
	);
};

fReadData = { arg value;
	if(value==1, {
		"## Reading data from file".postln;
		tReadData = Task(fReadDataLoop).start;
	}, {
		"## Stop reading data from file".postln;
		tReadData.stop;
	});
	readData = value;
};

fReadDataLoop = {
	var mags = Array.rand(100,0.0,1);
	var hues = Array.rand(100,0.0,1);
	var fileRead = FilePlayer.new(Document.dir++"Shackle/Data/Curves/DataDump.txt", delimiter: $;);
	var line = 0;
	inf.do {
		mags = fileRead.readAtLine(2*line)[0];
		if(mags=="", { line=0; mags = fileRead.readAtLine(2*line)[0]; }); // end of file reached
		mags = mags.subStrNoWrap(2,mags.size-3);
		mags = mags.split($,);
		mags.collect({ arg item, index; if(index > 0, {mags[index] = mags[index].asFloat}) });
		hues = fileRead.readAtLine(2*line+1)[0];
		hues = hues.subStrNoWrap(2,hues.size-3);
		hues = hues.split($,);
		hues.collect({ arg item, index; if(index > 1, {hues[index] = hues[index].asFloat}) });

		localAddr.sendBundle(nil, ['/mags']++mags[1..(mags.size-1)]);
		localAddr.sendBundle(nil, ['/hues']++hues[1..(hues.size-1)]);
		line = line + 1;
		(1/60).wait;
	};
};

fWriteData = { arg value;
	if(value==1, {
		"## Writing image data to logfile".postln;
		fileWrite = File.new(Document.dir++"Data/Curves/DataDump"++Date.getDate.stamp++".txt", "w"); // open logfile
	}, {
		fileWrite.close;
	});
	writeData = value;
};

///////////////////////////////////////////// gui //////////////////////////////////////

wCurves = (Window("Curves", Rect(580, 130, 490, 300)).background_(Color.white));
bFFTpack = (SmoothButton(wCurves, Rect(10,10,150,40))
	.border_(1).radius_(3).font_(Font("Helvetica", 20))
	.states_([ ["Resynthesis"], ["Resynthesis",Color.black, Color.green] ])
	.action_({ |b|
		if( (b.value == 1) && synthFFTpack.isNil, {
			synthFFTpack = Synth(\fftPack, [\volFFTBus, volFFTBus.index, \freqRangeBus, freqRangeBus.index]);
		}, {
			synthFFTpack.release; synthFFTpack = nil;
		});
	})
);
bRead = (SmoothButton(wCurves, Rect(175,10,135,40))
	.border_(1).radius_(3).font_(Font("Helvetica", 20))
	.states_([ ["Read Data"], ["Read Data",Color.black, Color.green] ])
	.action_({ |b|
		fReadData.value(b.value);
	})
	);
bImageCtrlSend = (SmoothButton(wCurves, Rect(325,10,150,40))
	.border_(1).radius_(3).font_(Font("Helvetica", 20))
	.states_([ ["Image Control"], ["Image Control",Color.black, Color.green] ])
	.action_({ |b| imageSendCtrlActive = b.value })
);
sFFTpack = (SmoothSlider(wCurves, Rect(10,55,465,40))
	.value_(0.5).border_(1).font_(Font("Helvetica", 12)).knobSize_(0.1)
	.string_(" Volume").align_(\left).stringColor_(Color.white)
	.action_({ |s|
		volFFTBus.set(spec.amp.at(s.value));
	})
);
sFreqRange = (SmoothSlider(wCurves, Rect(10,95,465,40))
	.value_(0.5).border_(1).font_(Font("Helvetica", 12)).knobSize_(0.1)
	.string_(" FreqRange").align_(\left).stringColor_(Color.white)
	.action_({ |s|
		freqRangeBus.set(s.value);
	})
);
tScene = (StaticText(wCurves, Rect(12,147,350,66))
	.align_(\topLeft).font_(Font("Helvetica",22)).string_("---")
);
tCountDown = (StaticText(wCurves, Rect(373,147,100,60))
	.align_(\bottom).font_(Font("Helvetica",55)).string_("").stringColor_(Color.black)
);

bDelay = (SmoothButton(wCurves, Rect(10,225,70,30))
	.border_(1).radius_(3).font_(Font("Helvetica", 12))
	.states_([ ["Delay"], ["Delay",Color.black, Color.green] ])
	.action_({ |b|
		fDelay.value(b.value);
		if(anneOnline == 1, { anneAddr.sendMsg("/Button1return", b.value); ("Button1return:" + b.value + "sent to Anne").postln; });
	})
);
sDelay = (SmoothSlider(wCurves, Rect(90,225,130,30))
	.value_(0.0).border_(1).knobSize_(0.1)
	.action_({ |s|
		volDelayBus.set(s.value);
	})
);
bWrite = (SmoothButton(wCurves, Rect(235,225,80,30))
	.border_(1).radius_(3).font_(Font("Helvetica", 14))
	.states_([ ["Write Data"], ["Write Data",Color.black, Color.green] ])
	.action_({ |b|
		fWriteData.value(b.value);
	})
	);
bOSCin = (SmoothButton(wCurves, Rect(325,225,70,30))
	.border_(1).radius_(3).font_(Font("Helvetica", 14))
	.states_([ ["OSC in"], ["OSC in",Color.black, Color.green] ])
	.action_({ |b|
		if(b.value==1,
			{ thisProcess.oscInMonitor(true, addr:1, excl: ['/InBus','/hid/ex3d', '/ard/ana', '/midi/control']) },
			{ thisProcess.oscInMonitor(false) });
	})
);
bOSCout = (SmoothButton(wCurves, Rect(405,225,70,30))
	.border_(1).radius_(3).font_(Font("Helvetica", 14))
	.states_([ ["OSC out"], ["OSC out",Color.black, Color.green] ])
	.action_({ |b|
		if(b.value==1, { ~oscOutMonitor = 1 }, { ~oscOutMonitor = 0 } )
	})
);

lapisStat = LapisStatus.new(win: wCurves, marginY: 265);

wCurves.view.keyDownAction_({
	arg view, char, modifiers, unicode, keycode;
	// page down -> next part
	if(keycode == 125, {
		sceneCount = (sceneCount + 2)%(scenes.size);
		if(modifiers.isAlt, {
			localAddr.sendMsg("/transition", scenes[sceneCount]);
		},{
			localAddr.sendMsg("/transition", scenes[sceneCount], "no-count");
		});
	});
	// page up -> prev part
	if(keycode == 126,{
		sceneCount = (sceneCount - 2)%(scenes.size);
		if(modifiers.isAlt, {
			localAddr.sendMsg("/transition", scenes[sceneCount]);
		},{
			localAddr.sendMsg("/transition", scenes[sceneCount], "no-count");
		});
    });
});

wCurves.onClose = {
	if(imageCtrlOnline==1, { tCurves.stop });
	imageCtrlAddr.disconnect;
	if(synthFFTpack.notNil, {synthFFTpack.release});
	synthDelay.release;
	OSCdef(\curvesNON).free; OSCdef(\curvesNOF).free; OSCdef(\curvesEx3d).free;
	OSCdef(\mags).free; OSCdef(\hues).free; OSCdef(\transition).free;
	OSCdef(\Slider1).free; OSCdef(\Slider2).free; OSCdef(\Slider3).free;
	OSCdef(\Button1).free; OSCdef(\Button2).free; OSCdef(\Button3).free;
	if(writeData==1, {fWriteData.value(0)}); // close logfile
	sceneAppClock.clear;
	if(readData==1, {tReadData.stop});
	taskCountDown.stop;
	lapisStat.stop;
	~wCurves = nil;
};
wCurves.front;
~wCurves = wCurves;


///////////////////////////////////////////// initialize //////////////////////////////////////

if(anneOnline == 1, { anneAddr.sendMsg("/Button1return", 0); ("Button1return: 0 sent to Anne").postln; });
if(imageCtrlOnline == 1, { tCurves = Task(fCurvesOSC).start });
localAddr.sendMsg("/transition", scenes[sceneCount], "no-count");

if(readData==1, {tReadData = Task(fReadDataLoop).start});
if(writeData==1, {fWriteData.value(1)});

)


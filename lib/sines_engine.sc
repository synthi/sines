//16 FM modulated sine waves
Engine_Sines : CroneEngine {

	var <synths;

	*new { arg context, doneCallback;
	^super.new(context, doneCallback);
}

alloc {
	//https://depts.washington.edu/dxscdoc/Help/Tutorials/Mark_Polishook_tutorial/18_Frequency_modulation.html
	SynthDef.new(\fm1, { arg out, freq = 440, carPartial = 1, modPartial = 1, index = 3, mul = 0.00, pan = 0, attackTime = 0.01, decayTime = 0.1;
		// index values usually are between 0 and 24
		// carPartial :: modPartial => car/mod ratio

		var mod;
		var car;
		var sig;
		var amp;
		var envelope;

		mod = SinOsc.ar(
			freq * modPartial,
			0,
			freq * index * LFNoise1.kr(5.reciprocal).abs
		);
		car = SinOsc.ar(
			freq * carPartial + mod,
			0,
			mul
		);
		//Looping AD envelope
		envelope = Env([0, 1, 0, 1], [0.1, attackTime, decayTime], releaseNode: 2, loopNode: 0);			
		//amp and out
		amp = EnvGen.kr(envelope, doneAction: Done.freeSelf);
		sig = Pan2.ar(car * amp, pan);			

		Out.ar(out, sig)			
	}).add;

	// make 16 synths, each using the def
	synths = Array.fill(16, {
		var out;
		var freq;
		var index;
		var mul;
		var pan;
		var attackTime; 
		var decayTime; 
		var params = [out, \freq, freq, \index, index, \mul, mul, \pan, pan, \attackTime, attackTime, \decayTime, decayTime];
		//params.postln;
		// this is where we supply the name of the def we made
		Synth.new(\fm1, params, target: context.og);
	});

	context.server.sync;

	(1..16).do({
		//pan settings
		this.addCommand(\pan, "ii", {
			arg msg;
			synths[msg[1]].set(\pan, msg[2]);
		});
		//index settings
		this.addCommand(\index, "ii", {
			arg msg;
			synths[msg[1]].set(\index, msg[2]);
		});
		//amp settings
		this.addCommand(\mul, "if", {
			arg msg;
			synths[msg[1]].set(\mul, msg[2]);
		});
		//freq settings
		this.addCommand(\freq, "ii", { 
			arg msg;
			synths[msg[1]].set(\freq, msg[2]);
		});
		//envelope settings
		this.addCommand(\envelope, "iii", { 
			arg msg;
			synths[msg[1]].set(\attackTime, msg[2]);
			synths[msg[1]].set(\decayTime, msg[3]);
		});
	});

}

//free the synths
free {
	synths[1].free;
	synths[2].free;
	synths[3].free;
	synths[4].free;
	synths[5].free;
	synths[6].free;
	synths[7].free;
	synths[8].free;
	synths[9].free;
	synths[10].free;
	synths[11].free;
	synths[12].free;
	synths[13].free;
	synths[14].free;
	synths[15].free;
	synths[16].free;
}

}


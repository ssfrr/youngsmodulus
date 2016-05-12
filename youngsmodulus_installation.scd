s.options.device = "8M"
s.options.numOutputBusChannels = 10
s.options.numOutputBusChannels = 2
s.boot

s.quit



////////////////////
// Create SynthDefs
///////////////////
(
// synthesize a single partial with a simple ASR envelope
SynthDef(\partialsynth, {
    | root=7.5, partial=32, amp=1, out=0 |
    // this is a little hacky because we can't set the initial value of Lag to give a fade-in,
    // so we use an Env to give a fade-in, which also handles freeing the synth
    // when the amplitude goes to zero
    var sig = SinOsc.ar(root*partial) * (Lag.kr(amp, 3) * Env.asr(3, 1, 3).kr(2, amp));
    Out.ar(out, sig);
}).add;

// simple 1-channel gain node for volume control of a whole bus. Note that the smoothing
// time on the amplitude matches the fade time of the partials.
// This also sends out the channel amplitude using SendTrig with the given trigger ID
SynthDef(\gain, {
    | amp=1, master=1, gate=1, in, out=0, trigID=0 |
    var sig = In.ar(in) * Lag.kr(amp, 10) * master * Env.asr(0.1, 1, 0.1).ar(2, gate);
    SendTrig.kr(Impulse.kr(20), trigID, PeakFollower.kr(sig, 0.999));
    Out.ar(out, sig);
}).add;

// buffer player, currently unused...
SynthDef(\loopbuf, {
    | bufnum, loopstart, loopend, out |
    Out.ar(out, LoopBuf.ar(1, bufnum, startLoop:loopstart, endLoop: loopend));
}).add;
)

x = Synth(\partialsynth)
x.set(\amp, 0)

/////////////////////////////////////////////////////////////
// Init main Synth structure with speaker groups and spatializers
////////////////////////////////////////////////////////////
(
~rootfreq = 30;
~ipadOSC = NetAddr.new("18.85.27.113", 9000);

// Create groups for each speaker location. We use `grp` here instead of `group`
// so that we can use ~frontleft.grp syntax (`group` is a method on Event).

// use an Event as a bag of attributes for each speaker location
// this is a list of channels for the speakers. There's some weird quirk of the 8M
// that is mapping the channels weirdly here
// ~speakers = [0, 1, 4, 5, 6, 7, 8, 9].collect {
~speakers = [0, 1].collect {
    | out, spidx |
    var gainbus = Bus.audio();
    var speaker = (
        grp: Group(),
        gainbus: gainbus,
        gainsynth: Synth(\gain, [in: gainbus, out: out, trigID: out], addAction:\addToTail),
        outbus: out,
        partials: nil!128,
        setgain: { | sp |
            var npartials = sp.partials.count {|x| x != nil };
            var gain = if (npartials == 0, { 0.6 }, { 0.6 / npartials });
            sp.gainsynth.set(\amp, gain);
        },
        setpartial: { | sp, partial, amp |
            var zerothresh = 0.001;
            var idx = partial-1;
            if((amp > zerothresh && sp.partials[idx].notNil), {
                sp.partials[idx][0].set(\amp, amp);
                sp.partials[idx][1] = amp;
            });
            if((amp > zerothresh && sp.partials[idx].isNil), {
                sp.partials[idx] = [Synth(\partialsynth,
                    [
                        root: ~rootfreq,
                        partial: partial,
                        amp: amp,
                        out: sp.gainbus
                ], sp.grp), amp];
                ~ipadOSC.sendMsg("/speaker/"++spidx++"/led/"++partial, 1);
            });
            if((amp <= zerothresh && sp.partials[idx].notNil), {
                sp.partials[idx][0].set(\amp, 0);
                sp.partials[idx] = nil;
                ~ipadOSC.sendMsg("/speaker/"++spidx++"/led/"++partial, 0);
            });
        }
    );
    // set up the harmonic OSC handlers
    (1..128).do {
        | harmonic |
        var path = ("/speaker/" ++ spidx ++ "/harm/" ++ harmonic).asSymbol;
        OSCdef(path,
            {
                | msg |
                var explevel = msg[1].linexp(0, 1, 0.001, 0.3);
                speaker.setpartial(harmonic, explevel);
        }, path);
    };

    speaker;
};

OSCdef(\coarse,
    {
        | msg |
        ~rootfreq = ~rootfreq * (1+(msg[1]*0.003));
        s.bind {
            ~speakers.do {
                |sp|
                sp.grp.set(\root, ~rootfreq)
            }
        }
    },
    '/coarse');

OSCdef(\fine,
    {
        | msg |
        ~rootfreq = ~rootfreq * (1 + (msg[1]*0.0003));
        s.bind {
            ~speakers.do {
                |sp|
                sp.grp.set(\root, ~rootfreq)
            }
        }
    },
    '/fine');


OSCdef(\dump,
    {
        | msg |
        (msg[1] == 1).if {
            "Root Freq: %\n".postf(~rootfreq);
            "Partials:".postln;
            "[".postln;
            ~speakers.do {
                |sp, i|
                // select all the non-nil partials
                var notnil = (1..sp.partials.size).select {|i| sp.partials[i-1] != nil};
                // print out a list of harmonic-amplitude pairs
                "%,\n".postf(notnil.collect {|i| [i, sp.partials[i-1][1]]});
            };
            "]".postln;
        }
    },
    '/dump';);

OSCdef(\master,
    {
        | msg |
        ~speakers.do {
            |sp|
			var mastergain = if(msg[1] == 0, 0, msg[1].linexp(0, 1, 0.002, 1));
			sp.gainsynth.set(\master, mastergain);
        }
    },
    '/master';);

// this handles the SendTrig messages from the Gain nodes, which send out the
// amplitude of that channel, with the Speaker number as the trigger ID
OSCdef(\tr,
    {
        | msg |
        var speaker = msg[2];
        var amp = msg[3].explin(0.01, 1, 0, 1);
        (~ipadOSC.notNil).if {
            ~ipadOSC.sendMsg("/speaker/"++speaker++"/level", amp);
        }
    },
    '/tr';)
)

~speakers[0].meterbus.get
0.90.explin(0.01, 1, 0, 1)

~ipadOSC.sendMsg("/speaker/"++0++"/led/"++2, 1);

////////////////////////////////
// SWITCH ON THE OSCILLATORS!
///////////////////////////////
(
// partial build-up code borrows from Sam Pluta's DreamHouse.scd code.  This
// duplicates the sine-wave frequencies of La Monte Young's composition playing
// at his and Marian Zazeela's Dream House installation in TriBeCa, NYC. The
// full title of the piece is:
//
// The Base 9:7:4 Symmetry in Prime Time When Centered above and below The
// Lowest Term Primes in The Range 288 to 224 with The Addition of 279 and 261
// in Which The Half of The Symmetric Division Mapped above and Including 288
// Consists of The Powers of 2 Multiplied by The Primes within The Ranges of
// 144 to 128, 72 to 64 and 36 to 32 Which Are Symmetrical to Those Primes in
// Lowest Terms in The Half of The Symmetric Division Mapped below and
// Including 224 within The Ranges 126 to 112, 63 to 56 and 31.5 to 28 with The
// Addition of 119


// start with the 9:7:4 base
var partials = IdentitySet[4, 7, 9];
// add the primes in the center band
(224..288).do{
    | i |
    if(i.isPrime, {
        partials.add(i);
    });
};
// additional partials
partials = partials ++ [261, 279];
//add the upper band of partials
//these are put in different octaves so that they are symetrical with the lower band
partials = partials ++ [71*(2**3), 17*(2**5), 67*(2**4), 137*(2**3), 131*(2**4), 139*(2**4)];
// add the lower band of partials
partials = partials ++ [31, 29, 61, 59, 113];
// add 119
partials.add(119);
//reinforce the b-ase frequencies within the 9:7 major third of the primary band
partials = partials ++ [2**8, 7*(2**5), 9*(2**5)];

~playpartials.value(partials)
)

// This is useful for quickly playing a set of partials through all speakers
(
~playpartials = {
	| partials |
	s.bind {
	~speakers.do {
		| speaker |
			partials.do {
				| partial |
				Synth(\partialsynth, [
					partial: partial,
					amp: 1/(~speakers.size * partials.size),
					out: speaker.outbus],
				speaker.grp);
			}
		}
	}
}
)

// this will play back a set of partials that have been dumped from the iOS app.
// It expects an array where each element has the partials for one speaker
// the partials are in an array where each element is a [harmonic, amplitude] pair
/*(
~loadpartials = {
    | speakers |
    s.bind {
        speakers.do {
            | partials, spidx |
            partials.do {
                | partial |
                var partidx = partial-1;
                if(~speakers[spidx].partials[partidx].isNil,
                    {
                        ~speakers[spidx].partials[partidx] =
                    }, {
                });
            }
        }
    }
}
)*/

// catalan numbers up as far as we can go without aliasing
~playpartials.value([1, 1, 2, 5, 14, 42, 132, 429, 1430])
~playpartials.value([ 4, 14, 15, 68, 8, 16, 20, 24, 67 ])
~playpartials.value([8]);
7.5*1430

// resonances measures using the 8th harmonic
// 6.11, 11.50Hz, 25.5, 63.15

// using 4th harmonic - 31Hz seems strong

// Some good harmonies - strong major triad, good shimmer (but not too dramatic), enough
// weird to be interesting. 67 gives some shimmer against 68
//Speaker 0 partials: [ 4, 14, 15, 68 ]
//Speaker 1 partials: [ 8, 16, 20, 24, 67 ]

(
////////////////////
// fade out the tones
///////////////////
s.bind {
    ~speakers.do {
        |sp|
        sp.grp.set(\gate, 0)
    }
}
)

//////////////////
// Set up an audio buffer
/////////////////
b = Buffer.read(s, "/Users/srussell/Desktop/IRCAM Workshop/WorkshopSounds/cello-VC_mV_cres3_4s_p-f_A2.aiff");

////////////////////
// Play the buffer through all 4 chanels
///////////////////
(
s.bind {
    // currently we're playing the same signal all the (virtual) speakers
    ~speakers.do {
        | speaker |
        Synth(\loopbuf, [
            bufnum: b,
            loopstart: s.sampleRate*2.0,
            loopend: s.sampleRate*2.400005,
            out: speaker.outbus],
        speaker.grp);
    }
}
)

(

////////////////////
// kill the loops
///////////////////
s.bind {
    ~speakers.do {
        |sp|
        sp.grp.freeAll;
    }
}
)

f = OSCFunc(_.postln, '/speaker/0/harm/2')
f.free
///////////////////////
// EXTRA SETUP NOTES:
//////////////////////

// get the OSC port
NetAddr.langPort
// turn on/off OSC tracing
OSCFunc.trace(true)
OSCFunc.trace(false)

// download atk-sounds and atk-kernels from:
// https://github.com/ambisonictoolkit/atk-sounds
// https://github.com/ambisonictoolkit/atk-kernels
// run the following block and unzip into the directory that pops up. The contents
// of the repos should be in "sounds" and "kernels" subfolders respectively
// also make sure to install the MathLib quark
(
Atk.createUserSupportDir;
Atk.openUserSupportDir;
)
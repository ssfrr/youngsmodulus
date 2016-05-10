s.boot
s.quit

//////////////////////////////
// set up encoder and decoder
/////////////////////////////
~encoder = FoaEncoderMatrix.newOmni;
~ambiout = Bus.audio(s, 4);
// choose your decoder
~decoder = FoaDecoderKernel.newCIPIC; // for binaural
~decoder = FoaDecoderMatrix.newStereo;

////////////////////
// Create SynthDefs
///////////////////
(
// synthesize a single partial with a simple ASR envelope
SynthDef(\partialsynth, {
    | root=7.5, partial=32, amp=1, gate=1, out=0 |
    var sig = SinOsc.ar(root*partial);
    var env = Env.asr(1, amp, 5).ar(2, gate);
    Out.ar(out, sig*env);
}).add;

// take the sound from a mono bus and apply spatialization based on distance and angle
SynthDef(\spat, {
    | dist=1, azimuth=0, elevation=0, mindist=1, maxdist=100, in, out=0 |
    var sndspeed = 344;
    // attenuate the volume
    var mult = Clip.kr(mindist/dist);
    var maxdelay = maxdist/sndspeed;
    // note we subtract out the 256-sample pre-delay for the HRIRs used for binaural decoding
    var delay = Clip.kr(dist/sndspeed - (256/44100), 0, maxdelay);
    // now the signal processing
    var delayed = DelayC.ar(In.ar(in), maxdist/sndspeed, Lag.kr(delay, 0.5)) * mult;
    var encoded = FoaEncode.ar(delayed, ~encoder);
    var transformed = FoaPush.ar(encoded, pi/2, azimuth, elevation);
    Out.ar(out, transformed);
}).add;

SynthDef(\decodebinaural, {
    | in, out=0, headAngle=0, headTilt=0, headTumble=0 |
    // rotate the world around the head, in the opposite direction.
    // TODO: I haven't put much thought into the rotation order here, so it's probably wrong
    var rotated = FoaRTT.ar(In.ar(in, 4), headAngle.neg, headTilt.neg, headTumble.neg);
    Out.ar(out, FoaDecode.ar(rotated, ~decoder));
}).add;

SynthDef(\loopbuf, {
    | bufnum, loopstart, loopend, out |
    Out.ar(out, LoopBuf.ar(1, bufnum, startLoop:loopstart, endLoop: loopend));
}).add;
)

/////////////////////////////////////////////////////////////
// Init main Synth structure with speaker groups and spatializers
////////////////////////////////////////////////////////////
(
// Create groups for each speaker location. We use `grp` here instead of `group`
// so that we can use ~frontleft.grp syntax (`group` is a method on Event).
// ATK uses the convention that +X is forward, +Y is left, and +Z is up (right-handed)
var setHeadLoc = {
    | self, loc |
    var diff = self.loc - loc;
    var dist = diff.squared.sum.sqrt;
    var ang = diff[1].atan2(diff[0]);
    //("diff: " ++ diff).postln;
    //("dist: " ++ dist).postln;
    //("azimuth: " ++ ang).postln;
    self.delaysynth.set(\dist, dist, \azimuth, ang);
};

// use an Event as a bag of attributes for each speaker location
// we spread the speaker locations slightly past where the listener can go
// so that we don't get weird singularities when they're right on top
~speakers = [[-2, -1.5, 0], [2, -1.5, 0], [-2, 1.5, 0], [2, 1.5, 0]].collect {
    | loc |
    var sp = (
        grp: Group(),
        loc: loc*1.01,
        outbus: Bus.audio,
        setHeadLoc: setHeadLoc,
    );
    sp.delaysynth = Synth(\spat, [in: sp.outbus, out: ~ambiout], addAction: \addToTail);

    sp
};

~decodesynth = Synth(\decodebinaural, [in: ~ambiout, out: 0], addAction: \addToTail);

~xyResp.free;
~xyResp = OSCFunc({
    | msg |
    // msg.postln;
    // in the ambisonic coordinate system +X is forward, +Y is left, +Z is up.
    // our room is 4mx3m with (0, 0) in the center
    // so we need to adapt the coords coming over OSC, which have 0, 0 in the
    // bottom-left, +Y forward, +X right
    ~speakers.do {
        | sp |
        sp.setHeadLoc([(msg[2]-0.5)*4, (0.5-msg[1])*3, 0]);
    }
}, '/xy');
~knobResp.free;
~knobResp = OSCFunc({
    | msg |
    // msg.postln;
    // positive angles move to the left, so we negate the knob
    ~decodesynth.set(\headAngle, msg[1].neg*pi);
}, '/knob')
)

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

~playpartials.value([1, 1, 2, 5, 14, 42, 132, 429, 1430, 4862, 16796])

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

///////////////////////
// EXTRA SETUP NOTES:
//////////////////////

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
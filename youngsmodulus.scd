s.boot
s.quit

(
SynthDef(\partialsynth, {
    | root=7.5, partial=32, amp=1, gate=1, out=0 |
    var sig = SinOsc.ar(root*partial);
    var env = Env.asr(1, amp, 5).ar(2, gate);
    Out.ar(out, sig*env);
}).add
)

~frontleft = Group()
~frontright = Group()

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
//reinforce the base frequencies within the 9:7 major third of the primary band
partials = partials ++ [2**8, 7*(2**5), 9*(2**5)];

// make sure all the synths start at exactly the same time
s.bind {
    // currently we're playing the same signal in the left and right speakers
    [[~frontleft, 0], [~frontright, 1]].do {
        | groupchan |
        var amp = 1/partials.size;
        partials.do {
            | partial |
            Synth(\partialsynth, [
                    partial: partial,
                    amp: amp,
                    out: groupchan[1]],
                groupchan[0]);
        }
    }
}
)

// fade out the tones
s.bind { [~frontleft, ~frontright].do(_.set(\gate, 0))}

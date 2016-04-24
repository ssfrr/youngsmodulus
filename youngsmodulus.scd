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
var partials = [64, 96, 128];
var amps = (1/partials.size)!partials.size;
partials = [partials, amps].flop;

// make sure all the synths start at exactly the same time
s.bind {
	// currently we're playing the same signal in the left and right speakers
	[[~frontleft, 0], [~frontright, 1]].do {
		| groupchan |
		partials.do {
			|pair|
			Synth(\partialsynth,
				[\partial, pair[0], \amp, pair[1], \out, groupchan[1]],
				groupchan[0]
			);}}}
)

// fade out the tones
s.bind { [~frontleft, ~frontright].do(_.set(\gate, 0))}

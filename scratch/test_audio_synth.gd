extends SceneTree

func _init() -> void:
	print("Testing procedural AudioStreamWAV generation...")
	var sample_rate := 22050
	var duration := 0.25
	var total_frames := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_frames * 2) # 16-bit mono = 2 bytes per frame
	
	for i in total_frames:
		var t := float(i) / float(sample_rate)
		# Frequency sweep from 880 down to 110
		var freq := lerpf(880.0, 110.0, t / duration)
		var env := exp(-t * 12.0)
		var val := sin(TAU * freq * t) * env
		var sample_val := clampi(int(val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample_val)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	print("AudioStreamWAV created successfully! Length: %.2f sec" % stream.get_length())
	quit(0)

extends Node

## 刻印的弹性合成音效组件；无外部音频依赖，缓存短音色并遵守已有 SFX 总线。
## 声音只接收展示事件，不参与库存、随机数或奖励结算。

## 合成采样率，短 UI 音效不需要占用高采样率内存。
const SAMPLE_RATE: int = 22050
## 各音色时长；缓存总量小于 100 KB。
const DURATIONS: Dictionary = {"charge": 0.55, "reveal": 0.22, "rare": 0.42, "claim": 0.38, "select": 0.075}
## 默认音量保留余量，避免叠加多个短音效时削波。
@export_range(-40.0, 0.0, 1.0) var volume_db: float = -16.0
## 可在检查器关闭本界面声音，不影响游戏主音量。
@export var sound_enabled: bool = true
## 音色缓存，每类只生成一次。
var _streams: Dictionary = {}
## 同时最多四个声音，循环复用，避免连续操作产生播放器泄漏。
var _players: Array[AudioStreamPlayer] = []
## 下一个复用播放器下标。
var _cursor: int = 0

## 播放指定音色；cue 为事件名，pitch 为音高倍率，返回值无。
func play_cue(cue: String, pitch: float = 1.0) -> void:
	if not sound_enabled or not is_inside_tree() or not DURATIONS.has(cue):
		return
	if _players.is_empty():
		_create_players()
	if not _streams.has(cue):
		_streams[cue] = _synthesize(cue)
	## 复用播放器让连续点击的内存与声音叠加都有明确上限。
	var player: AudioStreamPlayer = _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.stream = _streams[cue]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()

## 停止所有瞬态声音；无参数，返回值无。关闭和跳过使用此入口。
func stop_all() -> void:
	for player in _players:
		player.stop()

func _create_players() -> void:
	for index in 4:
		## 优先接入项目已有音效总线，缺少时回退到 Master。
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		add_child(player)
		_players.append(player)

func _synthesize(cue: String) -> AudioStreamWAV:
	## 每个音色一次性分配 PCM 数据，不在逐帧回调中合成。
	var duration: float = float(DURATIONS[cue])
	## 采样数使用整数，避免缓冲区尾部越界。
	var frame_count: int = int(duration * SAMPLE_RATE)
	## 16 位单声道字节序为小端，使用 Godot 自带编码方法。
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)
	for index in frame_count:
		## 时间以秒计，保证音调与帧率、游戏速度无关。
		var t: float = float(index) / float(SAMPLE_RATE)
		## 首尾淡入淡出避免界面操作产生爆音。
		var envelope: float = minf(t * 100.0, 1.0) * pow(maxf(0.0, 1.0 - t / duration), 2.0)
		## 音量峰值受控；叠加泛音后仍在 16 位范围内。
		var sample: float = 0.0
		match cue:
			"charge":
				sample = sin(TAU * (130.0 * t + 310.0 * t * t)) * 0.42 + sin(TAU * 95.0 * t) * 0.16
				envelope = minf(t * 4.0, 1.0) * minf((duration - t) * 8.0, 1.0)
			"reveal", "rare":
				sample = sin(TAU * (180.0 * t + 850.0 * (1.0 - exp(-t * 14.0)) / 14.0)) * 0.65
				if cue == "rare":
					sample += sin(TAU * 1046.5 * t) * 0.14 + sin(TAU * 1318.5 * t) * 0.09
			"claim":
				sample = sin(TAU * (330.0 * t + 420.0 * t * t)) * 0.45 + sin(TAU * 880.0 * t) * 0.1
			"select":
				sample = sin(TAU * 880.0 * t) * 0.3
		bytes.encode_s16(index * 2, int(clampf(sample * envelope, -1.0, 1.0) * 24000.0))
	## WAV 资源直接持有内存数据，不写入用户存档或临时音频文件。
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


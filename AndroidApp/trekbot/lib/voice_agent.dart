import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _available = false;
  Function(String)? onCommand;
  Function(bool)? onListeningStatusChanged;

  VoiceService({this.onListeningStatusChanged}) {
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  void _initSpeech() async {
    _available = await _speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          _restartListening();
        }
        onListeningStatusChanged?.call(status == 'listening');
      },
      onError: (error) {
        print('Error: $error');
        _isListening = false;
        _restartListening();
      },
    );
    if (_available) {
      print('Speech recognition service initialized');
      _startListening();
    } else {
      print('Speech recognition not available');
    }
  }

  void _startListening() {
    if (!_available || _isListening) {
      return;
    }
    _isListening = true;
    _speech.listen(
      onResult: (result) {
        print("Recognized Words: ${result.recognizedWords}");
        onCommand?.call(result.recognizedWords.split(' ').first);
        print("result : ${result.recognizedWords.split(' ').first}");
      },
      listenFor: Duration(seconds: 60),
      pauseFor: Duration(seconds: 30),
      localeId: "en_US",
      cancelOnError: false,
      partialResults: true,
    );
  }

  void _restartListening() {
    Future.delayed(Duration(seconds: 3), () {
      _startListening();
    });
  }

  void stopListening() {
    _speech.stop();
    _isListening = false;
  }
}

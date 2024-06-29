import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  Function(String)? onCommand;

  VoiceService() {
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  void _initSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          _startListening(); // Restart listening if it stops
        }
      },
      onError: (error) {
        print('Error: $error');
        _startListening(); // Restart listening on error
      },
    );
    if (available) {
      print('Speech recognition service initialized');
      _startListening();
    } else {
      print('Speech recognition not available');
    }
  }

  void _startListening() {
    if (_isListening) {
      return;
    }
    _isListening = true;
    _speech.listen(onResult: (result) {
      print(result);
      if (result.recognizedWords.toLowerCase().startsWith('alan')) {
        print("voice agent .....");
        // Trigger command handling
        onCommand?.call(result.recognizedWords.substring(4).trim());
      }
    });
  }

  void stopListening() {
    _speech.stop();
    _isListening = false;
  }
}

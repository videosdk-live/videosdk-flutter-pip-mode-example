import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_start/meeting_controls.dart';
import 'package:quick_start/pip_view.dart';
import 'package:videosdk/videosdk.dart';
import './participant_tile.dart';

class MeetingScreen extends StatefulWidget {
  final String meetingId;
  final String token;

  const MeetingScreen(
      {super.key, required this.meetingId, required this.token});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen>
    with WidgetsBindingObserver {
  late Room _room;
  var micEnabled = true;
  var camEnabled = true;
  final platform = MethodChannel('pip_channel');
  String _messageFromNative = 'No message yet';

  Map<String, Participant> participants = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Create room
    _room = VideoSDK.createRoom(
        roomId: widget.meetingId,
        token: widget.token,
        displayName: "John Doe",
        micEnabled: micEnabled,
        camEnabled: camEnabled,
        multiStream: false,
        defaultCameraIndex: kIsWeb ? 0 : 1);

    // Set meeting event listener
    setMeetingEventListener();

    // Join room
    _room.join();
    if (!kIsWeb && Platform.isAndroid) {
      platform.invokeMethod('setMeetingScreen', true);
      platform.setMethodCallHandler(_handleMethodCall);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'sendMessage':
        setState(() {
          _messageFromNative = call.arguments['message'];
        });
        if (_messageFromNative == "Done") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PiPView(room: _room),
            ),
          );
        }
        return 'Message received in Flutter';
      default:
        throw PlatformException(
          code: 'NotImplemented',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isAndroid) {
      platform.invokeMethod('setMeetingScreen', false);
    }
    if (!kIsWeb && Platform.isIOS) {
      platform.invokeMethod("dispose");
    }
    super.dispose();
  }

  void setMeetingEventListener() {
    _room.on(Events.roomJoined, () {
      print("meeting joined");
      if (!kIsWeb && Platform.isIOS) {
        VideoSDK.applyVideoProcessor(videoProcessorName: "processor");
        platform.invokeMethod("setupPiP");
      }
      setState(() {
        participants.putIfAbsent(
            _room.localParticipant.id, () => _room.localParticipant);
      });
    });

    _room.on(
      Events.participantJoined,
      (Participant participant) {
        setState(() {
          participants.putIfAbsent(participant.id, () => participant);
        });

        if (!kIsWeb && Platform.isIOS && participants.isNotEmpty) {
          participant.on(
            Events.streamEnabled,
            (Stream stream) {
              if (stream.kind == 'video') {
                print("flutter side stream ");
                String streamId = stream.id;
                platform.invokeMethod(
                  "remoteStream",
                  {
                    "remoteId": streamId,
                  },
                );
              }
            },
          );
        }
      },
    );

    _room.on(Events.error, (error) {
      print(
          "VIDEOSDK ERROR :: ${error['code']}  :: ${error['name']} :: ${error['message']}");
    });

    _room.on(Events.streamEnabled, (Stream stream) {
      setState(() {
        print("stream enable: $stream");
      });
    });

    _room.on(Events.participantLeft, (String participantId) {
      if (participants.containsKey(participantId)) {
        setState(() {
          participants.remove(participantId);
        });
      }
    });

    _room.on(Events.roomLeft, () {
      participants.clear();
      Navigator.popUntil(context, ModalRoute.withName('/'));
    });
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  Future<bool> _onWillPop() async {
    _room.leave();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _onWillPop(),
      child: Scaffold(
        appBar: AppBar(
          title: Text("Pip Mode"),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Text(widget.meetingId),
              Expanded(
                child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8.0,
                        mainAxisSpacing: 8.0,
                      ),
                      itemCount: participants.length,
                      itemBuilder: (context, index) {
                        return ParticipantTile(
                          participant: participants.values.elementAt(index),
                        );
                      },
                    )),
              ),
              MeetingControls(
                onToggleMicButtonPressed: () {
                  micEnabled ? _room.muteMic() : _room.unmuteMic();
                  micEnabled = !micEnabled;
                },
                onToggleCameraButtonPressed: () {
                  camEnabled ? _room.disableCam() : _room.enableCam();
                  camEnabled = !camEnabled;
                },
                onLeaveButtonPressed: () async {
                  _room.leave();
                },
                pipButtonPressed: () async {
                  enterPiPMode();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void enterPiPMode() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await platform.invokeMethod('enterPiPMode');
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PiPView(room: _room),
            ),
          );
        }
      } else if (!kIsWeb && Platform.isIOS) {
        try {
          await platform.invokeMethod('startPiP');
        } on PlatformException catch (e) {
          print("Failed to enter PiP: '${e.message}'.");
        }
      }
    } on PlatformException catch (e) {
      print("Failed to enter PiP mode: ${e.message}");
    }
  }
}

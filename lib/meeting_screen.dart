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
  String? activeStreamId;
  Map<String, Participant> participants = {};
  Map<String, bool> participantCameraStates = {};
  Map<String, String> participantStreamIds = {};
  bool _pipInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _room = VideoSDK.createRoom(
        roomId: widget.meetingId,
        token: widget.token,
        displayName: "John Doe",
        micEnabled: micEnabled,
        camEnabled: camEnabled,
        multiStream: false,
        defaultCameraIndex: kIsWeb ? 0 : 1);

    setMeetingEventListener();
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
    participants.clear();
    participantCameraStates.clear();
    participantStreamIds.clear();
    super.dispose();
  }

  void setMeetingEventListener() {
    _room.on(Events.roomJoined, () {
      if (!kIsWeb && Platform.isIOS && !_pipInitialized) {
        VideoSDK.applyVideoProcessor(videoProcessorName: "processor");
        platform.invokeMethod("setupPiP").then((_) {
          _pipInitialized = true;
        });
        platform.invokeMethod("remoteStream", {"remoteId": "Nothing"});
      }
      setState(() {
        participants[_room.localParticipant.id] = _room.localParticipant;
        participantCameraStates[_room.localParticipant.id] = camEnabled;
      });
    });

    _room.on(Events.participantJoined, (Participant participant) {
      setState(() {
        participants[participant.id] = participant;
        bool hasVideoStream =
            participant.streams.values.any((stream) => stream.kind == 'video');
        participantCameraStates[participant.id] = hasVideoStream;
        if (hasVideoStream) {
          var videoStream = participant.streams.values
              .firstWhere((stream) => stream.kind == 'video');
          participantStreamIds[participant.id] = videoStream.id;
        }

        if (!kIsWeb && Platform.isIOS) {
          String remoteId = hasVideoStream
              ? participantStreamIds[participant.id] ?? "No Cam"
              : "No Cam";
          platform.invokeMethod(
            "remoteStream",
            {"remoteId": remoteId},
          );
          if (hasVideoStream && activeStreamId == null) {
            activeStreamId = participantStreamIds[participant.id];
          }
        }
      });

      participant.on(Events.streamEnabled, (Stream stream) {
        if (stream.kind == 'video') {
          setState(() {
            participantCameraStates[participant.id] = true;
            participantStreamIds[participant.id] = stream.id;
            activeStreamId ??= stream.id;
          });
          if (!kIsWeb && Platform.isIOS) {
            platform.invokeMethod(
              "remoteStream",
              {"remoteId": stream.id},
            );
          }
        }
      });

      participant.on(Events.streamDisabled, (Stream stream) {
        if (stream.kind == 'video') {
          setState(() {
            participantCameraStates[participant.id] = false;
            if (activeStreamId == participantStreamIds[participant.id]) {
              activeStreamId =
                  _findNextActiveStreamId(excludeParticipantId: participant.id);
            }
            participantStreamIds.remove(participant.id);
          });
          if (!kIsWeb && Platform.isIOS) {
            String remoteId = activeStreamId ?? "No Cam";
            platform.invokeMethod(
              "remoteStream",
              {"remoteId": remoteId},
            );
          }
        }
      });
    });

    _room.on(Events.participantLeft, (String participantId) {
      setState(() {
        participants.remove(participantId);
        participantCameraStates.remove(participantId);
        String? leavingStreamId = participantStreamIds[participantId];
        participantStreamIds.remove(participantId);
        if (activeStreamId == leavingStreamId) {
          activeStreamId =
              _findNextActiveStreamId(excludeParticipantId: participantId);
        }
      });

      if (!kIsWeb && Platform.isIOS) {
        bool onlyLocalRemains = participants.length == 1 &&
            participants.containsKey(_room.localParticipant.id);
        String remoteId =
            onlyLocalRemains ? "Nothing" : (activeStreamId ?? "No Cam");
        platform.invokeMethod(
          "remoteStream",
          {
            "remoteId": remoteId,
          },
        );
      }
    });

    _room.on(Events.error, (error) {
      debugPrint(
          'MeetingScreen: VideoSDK Error - Code: ${error['code']}, Name: ${error['name']}, Message: ${error['message']}');
    });

    _room.on(Events.roomLeft, () {
      participants.clear();
      participantCameraStates.clear();
      participantStreamIds.clear();
      Navigator.popUntil(context, ModalRoute.withName('/'));
    });
  }

  String? _findNextActiveStreamId({String? excludeParticipantId}) {
    for (var participant in participants.values) {
      if (participant.id != excludeParticipantId &&
          participantCameraStates[participant.id] == true &&
          participantStreamIds.containsKey(participant.id)) {
        return participantStreamIds[participant.id];
      }
    }
    return null;
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
                  setState(() {});
                },
                onToggleCameraButtonPressed: () {
                  camEnabled ? _room.disableCam() : _room.enableCam();
                  camEnabled = !camEnabled;
                  setState(() {
                    participantCameraStates[_room.localParticipant.id] =
                        camEnabled;
                    if (camEnabled) {
                      var videoStream = _room.localParticipant.streams.values
                          .firstWhere((stream) => stream.kind == 'video');
                      participantStreamIds[_room.localParticipant.id] =
                          videoStream.id;
                      activeStreamId ??= videoStream.id;
                    } else {
                      participantStreamIds.remove(_room.localParticipant.id);
                      if (activeStreamId ==
                          participantStreamIds[_room.localParticipant.id]) {
                        activeStreamId = _findNextActiveStreamId(
                            excludeParticipantId: _room.localParticipant.id);
                      }
                    }
                  });
                  if (!kIsWeb && Platform.isIOS) {
                    String remoteId = camEnabled
                        ? (participantStreamIds[_room.localParticipant.id] ??
                            "No Cam")
                        : "No Cam";
                    platform.invokeMethod(
                      "remoteStream",
                      {"remoteId": remoteId},
                    );
                  }
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
        if (!_pipInitialized) {
          return;
        }
        try {
          await platform.invokeMethod('startPiP');
        } on PlatformException catch (e) {
          debugPrint('MeetingScreen: Failed to enter PiP on iOS: ${e.message}');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('MeetingScreen: Failed to enter PiP mode: ${e.message}');
    }
  }
}

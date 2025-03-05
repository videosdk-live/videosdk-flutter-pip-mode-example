import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_call.dart';
import 'meeting_screen.dart';

class JoinScreen extends StatelessWidget {
  final _meetingIdController = TextEditingController();

  JoinScreen({super.key});

  Future<void> requestPermissions(BuildContext context) async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera and Microphone permissions are required!")),
      );
    }
  }

  void onCreateButtonPressed(BuildContext context) async {
    await requestPermissions(context);
    
    await createMeeting().then((meetingId) {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MeetingScreen(
            meetingId: meetingId,
            token: token,
          ),
        ),
      );
    });
  }

  void onJoinButtonPressed(BuildContext context) {
    requestPermissions(context);

    String meetingId = _meetingIdController.text;
    var re = RegExp("\\w{4}\\-\\w{4}\\-\\w{4}");
    
    if (meetingId.isNotEmpty && re.hasMatch(meetingId)) {
      _meetingIdController.clear();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MeetingScreen(
            meetingId: meetingId,
            token: token,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please enter a valid meeting ID"),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VideoSDK QuickStart'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => onCreateButtonPressed(context),
              child: const Text('Create Meeting'),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(0, 8.0, 0, 8.0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Meeting Id',
                  border: OutlineInputBorder(),
                ),
                controller: _meetingIdController,
              ),
            ),
            ElevatedButton(
              onPressed: () => onJoinButtonPressed(context),
              child: const Text('Join Meeting'),
            ),
          ],
        ),
      ),
    );
  }
}
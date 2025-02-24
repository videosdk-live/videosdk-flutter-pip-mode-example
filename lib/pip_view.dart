import 'package:flutter/material.dart';
import 'package:videosdk/videosdk.dart';
import './participant_tile.dart';

class PiPView extends StatefulWidget {
  final Room room;

  const PiPView({super.key, required this.room});

  @override
  State<PiPView> createState() => _PiPViewState();
}

class _PiPViewState extends State<PiPView> with WidgetsBindingObserver {
  late Room _room;
  Map<String, Participant> participants = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _room = widget.room;
    setMeetingEventListener();

    // Initialize participants list
    participants.putIfAbsent(
        _room.localParticipant.id, () => _room.localParticipant);
    participants.addAll(_room.participants);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void setMeetingEventListener() {
    _room.on(Events.participantJoined, (Participant participant) {
      setState(() {
        participants.putIfAbsent(participant.id, () => participant);
      });
    });

    _room.on(Events.participantLeft, (String participantId) {
      setState(() {
        participants.remove(participantId);
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Participant> participantList = participants.values.toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: 200,
          height: 120,
          child: _buildParticipantsView(participantList),
        ),
      ),
    );
  }

  Widget _buildParticipantsView(List<Participant> participantList) {
    if (participantList.length == 1) {
      return Row(
        children: [
          Expanded(child: ParticipantTile(participant: _room.localParticipant)),
          Expanded(
            child: Container(
              color: Colors.grey.shade800,
              child: const Center(
                child: Text(
                  "Only one participant in the meeting",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // Show local and one remote participant
      Participant localParticipant = _room.localParticipant;
      Participant remoteParticipant = participantList.firstWhere(
        (p) => p.id != localParticipant.id,
        orElse: () => participantList[1],
      );

      return Row(
        children: [
          Expanded(child: ParticipantTile(participant: localParticipant)),
          Expanded(child: ParticipantTile(participant: remoteParticipant)),
        ],
      );
    }
  }
}

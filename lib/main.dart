import 'package:flutter/material.dart';

// Import local files that I need to run the app
import 'sight/smallest_noticeable_size.dart';
import 'sight/contrast_finder.dart';
import 'sight/outcomes_page.dart';
import 'sound/pitch_frequency_range.dart';
import 'sound/amplitude_jnd.dart';
import 'sound/pitch_jnd.dart';
import 'sound/sound_gap_detection.dart';
import 'utils/screen_calibration_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health sensing trials',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const TrialHomePage(),
    );
  }
}

class TrialHomePage extends StatelessWidget {
  const TrialHomePage({super.key});

  static TextStyle _sectionTitle(BuildContext context) {
    final base = Theme.of(context).textTheme.titleSmall;
    return (base ?? const TextStyle(fontSize: 14)).copyWith(
      fontWeight: FontWeight.w600,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trials'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose a trial:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                Text('Visual Trials', style: _sectionTitle(context)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScreenCalibrationPage(),
                      ),
                    );
                  },
                  child: const Text('Calibrate Screen'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ContrastFinder(),
                      ),
                    );
                  },
                  child: const Text('Contrast Finder'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SmallestNoticeableSizePage(),
                      ),
                    );
                  },
                  child: const Text('E Rotation Trial'),
                ),
                const SizedBox(height: 20),
                Text('Sound Trials', style: _sectionTitle(context)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PitchFrequencyRangePage(),
                      ),
                    );
                  },
                  child: const Text('Pitch Frequency Range'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SoundGapDetectionPage(),
                      ),
                    );
                  },
                  child: const Text('Sound Gap Detection'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PitchJndPage(),
                      ),
                    );
                  },
                  child: const Text('Pitch Just Noticeable Difference'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AmplitudeJndPage(),
                      ),
                    );
                  },
                  child: const Text('Amplitude Just Noticeable Difference'),
                ),
                const SizedBox(height: 20),
                Text('All Outcomes and Charts', style: _sectionTitle(context)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OutcomesPage(),
                      ),
                    );
                  },
                  child: const Text('All Outcomes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

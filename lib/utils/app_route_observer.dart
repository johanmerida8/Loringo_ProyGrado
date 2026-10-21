// lib/utils/app_route_observer.dart
//
// App-wide RouteObserver, registered on MaterialApp.navigatorObservers in
// main.dart. Lets a screen (via RouteAware) know when it becomes visible
// again after the route above it is popped -- e.g.
// student_activities_screen.dart waits for this before showing the league
// ascension pop-up, since ActivityPlayScreen/QuizPlayScreen hand off to
// ActivityCompleteScreen with pushReplacement, which completes the
// original push() future while the completion screen is still on top.
import 'package:flutter/widgets.dart';

final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

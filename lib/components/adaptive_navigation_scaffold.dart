import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AdaptiveNavigationScaffold extends StatelessWidget {

  final String title;
  final Widget sidebarContent;
  final Widget body;
  final Widget? bottomNavigatorBar;
  final Widget? floatingActionButton;
  final Color appBarColor;
  final double desktopSidebarWidth;
  final double desktopBreakpoint;

  const AdaptiveNavigationScaffold({
    super.key,
    required this.title,
    required this.sidebarContent,
    required this.body,
    this.bottomNavigatorBar,
    this.floatingActionButton,
    this.appBarColor = const Color(0xFF4CAF50),
    this.desktopSidebarWidth = 280,
    this.desktopBreakpoint = 1000,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktopWeb = kIsWeb && width >= desktopBreakpoint;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: isDesktopWeb ? null : Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu', 
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      drawer: isDesktopWeb ? null : Drawer(
        backgroundColor: Colors.white,
        child: sidebarContent,
      ),
      floatingActionButton: floatingActionButton,
      body: isDesktopWeb
          ? Row(
            children: [
              SizedBox(
                width: desktopSidebarWidth,
                child: Material(
                  color: Colors.white,
                  elevation: 1,
                  child: sidebarContent,
                ),
              ),
              Expanded(child: body),
            ],
          )
          : body,
        bottomNavigationBar: isDesktopWeb ? null : bottomNavigatorBar,
    );
  }
}
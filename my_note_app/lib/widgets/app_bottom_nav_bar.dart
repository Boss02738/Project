import 'package:flutter/material.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Future<void> Function(int) onTapAsync;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTapAsync,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      onTap: (i) => onTapAsync(i),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: 'Home',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(
          icon: Icon(Icons.description_outlined),
          label: 'Document',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_circle_outlined),
          label: 'Profile',
        ),
      ],
    );
  }
}

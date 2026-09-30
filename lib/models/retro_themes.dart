import 'package:flutter/material.dart';

class RetroTheme {
  final String name;
  final Color deviceColor;
  final Color screenColor;
  final Color dpadColor;
  final Color okColor;
  final Color menuColor;
  final Color playColor;
  final Color mixColor;
  final Color backColor;
  final Color ledColor;

  const RetroTheme({
    required this.name,
    required this.deviceColor,
    required this.screenColor,
    required this.dpadColor,
    required this.okColor,
    required this.menuColor,
    required this.playColor,
    required this.mixColor,
    required this.backColor,
    required this.ledColor,
  });
}

final List<RetroTheme> retroThemes = [
  const RetroTheme(
    name: 'CLASSIC TEAL',
    deviceColor: Color(0xFF43908C),
    screenColor: Color(0xFFD4A574),
    dpadColor: Color(0xFFEADB7B),
    okColor: Color(0xFF132382),
    menuColor: Color(0xFF0F5234),
    playColor: Color(0xFF28D0E7),
    mixColor: Color(0xFF56B55E),
    backColor: Color(0xFFDB4639),
    ledColor: Color(0xFFFF2222),
  ),
  const RetroTheme(
    name: 'GAMEBOY',
    deviceColor: Color(0xFF9B9B84),
    screenColor: Color(0xFF8BAC0F),
    dpadColor: Color(0xFF333333),
    okColor: Color(0xFF0F380F),
    menuColor: Color(0xFF306230),
    playColor: Color(0xFF8BAC0F),
    mixColor: Color(0xFF306230),
    backColor: Color(0xFF0F380F),
    ledColor: Color(0xFFFF3333),
  ),
  const RetroTheme(
    name: 'ARCADE RED',
    deviceColor: Color(0xFF2C2C2C),
    screenColor: Color(0xFFFFB000),
    dpadColor: Color(0xFF444444),
    okColor: Color(0xFFCC0000),
    menuColor: Color(0xFF0066CC),
    playColor: Color(0xFF00CC66),
    mixColor: Color(0xFFFF6600),
    backColor: Color(0xFF990000),
    ledColor: Color(0xFF00FF66),
  ),
  const RetroTheme(
    name: 'CYBERPUNK',
    deviceColor: Color(0xFF1A0033),
    screenColor: Color(0xFF00FFCC),
    dpadColor: Color(0xFFFF007F),
    okColor: Color(0xFF00FFFF),
    menuColor: Color(0xFFFF007F),
    playColor: Color(0xFF00FFCC),
    mixColor: Color(0xFF9900FF),
    backColor: Color(0xFFFF0033),
    ledColor: Color(0xFF00FFFF),
  ),
];

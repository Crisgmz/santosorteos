import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget instagramLink(String username, String url) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Text(
        username,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}

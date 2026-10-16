import 'package:flutter/material.dart';

class CategoryInfo {
  const CategoryInfo(this.key, this.label, this.icon, this.light, this.dark);

  final String key;
  final String label;
  final IconData icon;
  final Color light;
  final Color dark;

  Color colorFor(Brightness b) => b == Brightness.dark ? dark : light;
}

/// Must match CATEGORIES in backend/app/models.py.
const List<CategoryInfo> kCategories = [
  CategoryInfo('food', 'Food', Icons.restaurant_rounded, Color(0xFFE8590C), Color(0xFFFF922B)),
  CategoryInfo('groceries', 'Groceries', Icons.local_grocery_store_rounded, Color(0xFF2F9E44), Color(0xFF69DB7C)),
  CategoryInfo('transport', 'Transport', Icons.directions_car_rounded, Color(0xFF1971C2), Color(0xFF74C0FC)),
  CategoryInfo('shopping', 'Shopping', Icons.shopping_bag_rounded, Color(0xFFC2255C), Color(0xFFF783AC)),
  CategoryInfo('bills', 'Bills', Icons.receipt_long_rounded, Color(0xFF6741D9), Color(0xFFB197FC)),
  CategoryInfo('entertainment', 'Fun', Icons.movie_rounded, Color(0xFFE67700), Color(0xFFFFD43B)),
  CategoryInfo('health', 'Health', Icons.favorite_rounded, Color(0xFFC92A2A), Color(0xFFFF8787)),
  CategoryInfo('travel', 'Travel', Icons.flight_rounded, Color(0xFF0C8599), Color(0xFF66D9E8)),
  CategoryInfo('education', 'Education', Icons.school_rounded, Color(0xFF5C940D), Color(0xFFA9E34B)),
  CategoryInfo('other', 'Other', Icons.more_horiz_rounded, Color(0xFF495057), Color(0xFFADB5BD)),
];

final Map<String, CategoryInfo> _byKey = {for (final c in kCategories) c.key: c};

CategoryInfo categoryInfo(String key) => _byKey[key] ?? kCategories.last;

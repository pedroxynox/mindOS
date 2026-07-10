import 'package:flutter/material.dart';

/// Visual style (Spanish label, icon, colour) for each derived node type, so
/// every screen shows the graph consistently.
class NodeTypeStyle {
  const NodeTypeStyle({
    required this.singular,
    required this.plural,
    required this.icon,
    required this.color,
  });

  final String singular;
  final String plural;
  final IconData icon;
  final Color color;

  static NodeTypeStyle of(String type) {
    switch (type) {
      case 'task':
        return const NodeTypeStyle(
          singular: 'Tarea',
          plural: 'Tareas',
          icon: Icons.check_circle_outline,
          color: Color(0xFF2E7D32),
        );
      case 'person':
        return const NodeTypeStyle(
          singular: 'Persona',
          plural: 'Personas',
          icon: Icons.person_outline,
          color: Color(0xFF1565C0),
        );
      case 'project':
        return const NodeTypeStyle(
          singular: 'Proyecto',
          plural: 'Proyectos',
          icon: Icons.folder_outlined,
          color: Color(0xFF6A1B9A),
        );
      case 'event':
        return const NodeTypeStyle(
          singular: 'Evento',
          plural: 'Eventos',
          icon: Icons.event_outlined,
          color: Color(0xFFC62828),
        );
      case 'topic':
        return const NodeTypeStyle(
          singular: 'Tema',
          plural: 'Temas',
          icon: Icons.label_outline,
          color: Color(0xFF00838F),
        );
      case 'decision':
        return const NodeTypeStyle(
          singular: 'Decisión',
          plural: 'Decisiones',
          icon: Icons.flag_outlined,
          color: Color(0xFFEF6C00),
        );
      case 'note':
        return const NodeTypeStyle(
          singular: 'Nota',
          plural: 'Notas',
          icon: Icons.sticky_note_2_outlined,
          color: Color(0xFF546E7A),
        );
      default:
        return NodeTypeStyle(
          singular: type,
          plural: type,
          icon: Icons.circle_outlined,
          color: const Color(0xFF546E7A),
        );
    }
  }

  /// Human, Spanish label for a relationship type between nodes.
  static String edgeLabel(String type) {
    switch (type) {
      case 'assigned_to':
        return 'asignado a';
      case 'relates_to':
        return 'se relaciona con';
      case 'mentions':
        return 'menciona a';
      case 'part_of':
        return 'parte de';
      case 'depends_on':
        return 'depende de';
      case 'scheduled_for':
        return 'agendado para';
      default:
        return type.replaceAll('_', ' ');
    }
  }
}

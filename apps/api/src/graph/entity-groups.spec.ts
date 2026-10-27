import { NodeType } from '@prisma/client';
import { normalizeLabel } from '../common/text';
import {
  entityKey,
  groupEntities,
  GroupableNode,
  sameEntity,
  snippet,
} from './entity-groups';

/**
 * Entities are grouped by type + normalised name (mejoras-v2 §D): the same
 * rules as the AI's `normalize_label`, newest mention first, deterministic
 * order so the offset cursor is stable.
 */
function n(
  id: string,
  title: string | null,
  createdAt: string,
  extra: Partial<GroupableNode> = {},
): GroupableNode {
  return {
    id,
    type: 'person' as NodeType,
    title,
    confidence: 0.8,
    occurredAt: null,
    createdAt: new Date(createdAt),
    ...extra,
  };
}

describe('normalizeLabel', () => {
  it.each([
    ['Marcos', 'marcos'],
    ['  MÁRCOS. ', 'marcos'],
    ['¿Reunión   de equipo?', 'reunion de equipo'],
    ['"São Paulo"', 'sao paulo'],
    ['—', ''],
  ])('%j → %j (same rules as the AI side)', (input, expected) => {
    expect(normalizeLabel(input)).toBe(expected);
  });
});

describe('groupEntities', () => {
  it('collapses mentions of the same name, newest first', () => {
    const groups = groupEntities([
      n('a', 'Marcos', '2026-10-01T10:00:00Z', { confidence: 0.6 }),
      n('b', 'Ana', '2026-10-03T10:00:00Z'),
      n('c', 'márcos', '2026-10-05T10:00:00Z', { confidence: 0.9 }),
    ]);

    expect(groups.map((g) => g.title)).toEqual(['márcos', 'Ana']);
    expect(groups[0]).toMatchObject({
      representativeId: 'c',
      nodeIds: ['c', 'a'],
      mentions: 2,
      confidence: 0.9,
    });
    expect(groups[0].firstSeenAt.toISOString()).toBe(
      '2026-10-01T10:00:00.000Z',
    );
    expect(groups[0].lastSeenAt.toISOString()).toBe('2026-10-05T10:00:00.000Z');
  });

  it('never merges different types or untitled nodes', () => {
    const groups = groupEntities([
      n('p', 'Aurora', '2026-10-01T10:00:00Z'),
      n('q', 'Aurora', '2026-10-01T10:00:00Z', { type: 'project' }),
      n('x', null, '2026-10-01T10:00:00Z'),
      n('y', '  ', '2026-10-01T10:00:00Z'),
    ]);
    expect(groups).toHaveLength(4);
  });

  it('orders ties deterministically', () => {
    const rows = [
      n('1', 'Bea', '2026-10-01T10:00:00Z'),
      n('2', 'Ana', '2026-10-01T10:00:00Z'),
    ];
    const once = groupEntities(rows).map((g) => g.title);
    const again = groupEntities([...rows].reverse()).map((g) => g.title);
    expect(once).toEqual(['Ana', 'Bea']);
    expect(again).toEqual(once);
  });
});

describe('sameEntity', () => {
  const marcos = n('a', 'Marcos', '2026-10-01T10:00:00Z');
  const others = [
    marcos,
    n('b', 'MARCOS', '2026-10-02T10:00:00Z'),
    n('c', 'Ana', '2026-10-02T10:00:00Z'),
  ];

  it('returns every mention of the name', () => {
    expect(sameEntity(marcos, others).map((m) => m.id)).toEqual(['a', 'b']);
  });

  it('keeps tasks and notes one by one', () => {
    const task = { ...marcos, type: 'task' as NodeType };
    expect(sameEntity(task, others)).toEqual([task]);
  });

  it('always includes the node itself', () => {
    expect(sameEntity(marcos, []).map((m) => m.id)).toEqual(['a']);
    expect(entityKey(marcos)).toBe(entityKey(others[1]));
  });
});

describe('snippet', () => {
  it('keeps short text and cuts long text on a word', () => {
    expect(snippet('  Llamar a\n Marcos ')).toBe('Llamar a Marcos');
    const long = 'palabra '.repeat(40);
    const cut = snippet(long, 50);
    expect(cut.length).toBeLessThanOrEqual(51);
    expect(cut.endsWith('…')).toBe(true);
    expect(cut).not.toMatch(/\s…$/);
    expect(snippet(null)).toBe('');
  });
});

/**
 * Canonical expense categories (mejoras-v2 §E). The AI's expense detector,
 * the API and the app share these keys; the app shows them in Spanish.
 */
export const EXPENSE_CATEGORIES = [
  'food',
  'transport',
  'home',
  'health',
  'leisure',
  'shopping',
  'bills',
  'education',
  'other',
] as const;
export type ExpenseCategory = (typeof EXPENSE_CATEGORIES)[number];

const fold = (s: string): string =>
  s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .replace(/\s+/g, ' ')
    .trim();

/**
 * Words people typed as a category before there was a selector (free text,
 * es/pt/en), mapped to a canonical key. Accent-free and lowercase.
 */
const SYNONYMS: Record<ExpenseCategory, string[]> = {
  food: [
    'comida',
    'alimentacion',
    'alimentos',
    'restaurante',
    'restaurant',
    'super',
    'supermercado',
    'mercado',
    'groceries',
    'cafe',
    'almuerzo',
    'cena',
    'desayuno',
    'delivery',
    'almoco',
    'lanche',
    'jantar',
    'meal',
  ],
  transport: [
    'transporte',
    'uber',
    'taxi',
    'gasolina',
    'combustible',
    'combustivel',
    'nafta',
    'bus',
    'colectivo',
    'onibus',
    'metro',
    'subte',
    'parking',
    'estacionamiento',
    'peaje',
    'fuel',
  ],
  home: [
    'casa',
    'hogar',
    'alquiler',
    'renta',
    'arriendo',
    'aluguel',
    'rent',
    'muebles',
    'limpieza',
    'mantenimiento',
  ],
  health: [
    'salud',
    'saude',
    'farmacia',
    'medico',
    'doctor',
    'dentista',
    'medicina',
    'remedios',
    'gimnasio',
    'gym',
    'pharmacy',
  ],
  leisure: [
    'ocio',
    'entretenimiento',
    'diversion',
    'lazer',
    'cine',
    'bar',
    'salidas',
    'viaje',
    'viajes',
    'streaming',
    'juegos',
    'entertainment',
    'fun',
    'travel',
  ],
  shopping: [
    'compras',
    'ropa',
    'roupa',
    'regalo',
    'regalos',
    'electronica',
    'tecnologia',
    'clothes',
    'gifts',
  ],
  bills: [
    'servicios',
    'cuentas',
    'facturas',
    'luz',
    'agua',
    'gas',
    'internet',
    'telefono',
    'celular',
    'seguro',
    'impuestos',
    'contas',
    'utilities',
  ],
  education: [
    'educacion',
    'educacao',
    'curso',
    'cursos',
    'libro',
    'libros',
    'escuela',
    'colegio',
    'universidad',
    'matricula',
    'books',
    'school',
  ],
  other: ['otros', 'otro', 'outros', 'varios', 'misc'],
};

const LOOKUP = new Map<string, ExpenseCategory>();
for (const key of EXPENSE_CATEGORIES) {
  LOOKUP.set(key, key);
  for (const word of SYNONYMS[key]) LOOKUP.set(word, key);
}

/** Canonical key of a stored or typed category; unknown → `other`. */
export function canonicalCategory(raw: unknown): ExpenseCategory {
  if (typeof raw !== 'string') return 'other';
  return LOOKUP.get(fold(raw)) ?? 'other';
}

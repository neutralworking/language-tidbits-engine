-- Seed topics for testing the content pipeline
-- Run: psql -U $POSTGRES_USER -d $POSTGRES_DB -f db/seed-topics.sql

INSERT INTO topics (slug, raw_topic, category, channel, priority) VALUES
    ('ok-origin',           'Origin of the word OK',                        'etymology',        'language-tidbits', 'high'),
    ('emoji-language',      'How emoji became a universal language',        'modern-language',   'language-tidbits', 'high'),
    ('click-languages',     'The click languages of Southern Africa',       'phonetics',        'language-tidbits', 'medium'),
    ('japanese-writing',    'Why Japanese has three writing systems',        'writing-systems',  'language-tidbits', 'medium'),
    ('english-spelling',    'Why English spelling is so inconsistent',      'orthography',      'language-tidbits', 'high'),
    ('no-word-for-blue',    'Languages that have no word for blue',         'color-terms',      'language-tidbits', 'medium'),
    ('alphabet-order',      'How the alphabet got its order',               'writing-systems',  'language-tidbits', 'medium'),
    ('dream-language',      'The language you dream in',                    'psycholinguistics', 'language-tidbits', 'high'),
    ('english-loanwords',   'Words English stole from other languages',     'etymology',        'language-tidbits', 'high'),
    ('longest-word',        'The longest word in English debate',           'vocabulary',       'language-tidbits', 'low')
ON CONFLICT (slug) DO NOTHING;

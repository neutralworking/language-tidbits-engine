#!/usr/bin/env python3
"""
ingest.py — Fetch Wikipedia + Reddit sources for pending topics and store in Postgres.

Standalone version of the v2-source-ingestion n8n workflow. Useful for testing
the pipeline without configuring n8n credentials.

Usage:
    python3 scripts/ingest.py                  # process all pending topics
    python3 scripts/ingest.py --limit 1        # process one topic
    python3 scripts/ingest.py --topic ok-origin # process a specific slug
    python3 scripts/ingest.py --seed           # seed sample topics first
    python3 scripts/ingest.py --status         # show topic/source counts

Requires: psycopg2 (pip install psycopg2-binary)
"""

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path


def load_env(repo_dir: Path) -> None:
    env_file = repo_dir / ".env"
    if not env_file.exists():
        return
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())


def get_db_conn():
    try:
        import psycopg2
    except ImportError:
        print("Error: psycopg2 not installed. Run: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)

    return psycopg2.connect(
        host=os.environ.get("POSTGRES_HOST", "localhost"),
        port=int(os.environ.get("POSTGRES_PORT", "5432")),
        dbname=os.environ.get("POSTGRES_DB", "language_tidbits"),
        user=os.environ.get("POSTGRES_USER", "tidbits"),
        password=os.environ.get("POSTGRES_PASSWORD", "changeme"),
    )


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


USER_AGENT = "language-tidbits-engine/1.0 (content research; https://github.com/neutralworking/language-tidbits-engine)"


def fetch_json(url: str, headers: dict = None) -> dict | None:
    req = urllib.request.Request(url)
    req.add_header("User-Agent", USER_AGENT)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as e:
        print(f"  Warning: {url} — {e}")
        return None


def search_wikipedia(topic: str) -> str | None:
    """Search Wikipedia and return the best matching page title."""
    q = urllib.request.quote(topic)
    url = f"https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={q}&srlimit=3&format=json"
    data = fetch_json(url)
    results = (data or {}).get("query", {}).get("search", [])
    if results:
        return results[0]["title"]
    return None


def fetch_wikipedia_summary(topic: str) -> dict | None:
    title = search_wikipedia(topic)
    if not title:
        return None
    slug = title.replace(" ", "_")
    url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{urllib.request.quote(slug)}"
    return fetch_json(url)


def fetch_wikipedia_html(topic: str) -> dict | None:
    title = search_wikipedia(topic)
    if not title:
        return None
    url = f"https://en.wikipedia.org/w/api.php?action=parse&page={urllib.request.quote(title)}&prop=text|sections|categories&format=json&redirects=1"
    return fetch_json(url)


def fetch_reddit(topic: str) -> list | None:
    """Search Reddit via Pullpush (free archive API, no OAuth needed)."""
    q = urllib.request.quote(topic)
    url = f"https://api.pullpush.io/reddit/search/submission/?q={q}&sort=score&sort_type=desc&size=10"
    data = fetch_json(url)
    if data and "data" in data:
        return data["data"]
    return None


def strip_html(html: str) -> str:
    import re
    text = re.sub(r"<[^>]+>", " ", html)
    text = re.sub(r"\s+", " ", text)
    return text.strip()[:50000]


def upsert_source(cur, doc: dict) -> bool:
    cur.execute("""
        INSERT INTO source_documents (topic_id, source_type, source_url, source_id, title, content_text, content_html, author, score, metadata, content_hash)
        VALUES (%(topic_id)s, %(source_type)s, %(source_url)s, %(source_id)s, %(title)s, %(content_text)s, %(content_html)s, %(author)s, %(score)s, %(metadata)s, %(content_hash)s)
        ON CONFLICT (topic_id, source_type, source_id) DO UPDATE
        SET content_text = EXCLUDED.content_text,
            content_hash = EXCLUDED.content_hash,
            fetched_at = now()
        RETURNING id
    """, doc)
    return cur.fetchone() is not None


def ingest_topic(cur, topic_id: str, raw_topic: str, slug: str) -> int:
    """Fetch sources for a topic. Returns number of documents stored."""
    print(f"\n--- {slug} ({raw_topic}) ---")
    stored = 0

    # Mark ingesting
    cur.execute("UPDATE topics SET status = 'ingesting', updated_at = now() WHERE id = %s", (topic_id,))

    # Wikipedia summary
    print("  Fetching Wikipedia summary...")
    summary = fetch_wikipedia_summary(raw_topic)
    if summary and summary.get("extract"):
        text = summary["extract"]
        doc = {
            "topic_id": topic_id,
            "source_type": "wikipedia",
            "source_url": (summary.get("content_urls", {}).get("desktop", {}).get("page", "")),
            "source_id": str(summary.get("pageid", "")),
            "title": summary.get("title", raw_topic),
            "content_text": text,
            "content_html": summary.get("extract_html", ""),
            "author": None,
            "score": None,
            "metadata": json.dumps({
                "description": summary.get("description", ""),
                "thumbnail": (summary.get("thumbnail", {}) or {}).get("source", ""),
                "doc_subtype": "summary",
            }),
            "content_hash": sha256(text),
        }
        if upsert_source(cur, doc):
            stored += 1
            print(f"  ✓ Wikipedia summary ({len(text)} chars)")
    else:
        print("  ✗ No Wikipedia summary found")

    time.sleep(1)  # rate limit

    # Wikipedia full page
    print("  Fetching Wikipedia full page...")
    html_data = fetch_wikipedia_html(raw_topic)
    if html_data and html_data.get("parse", {}).get("text"):
        raw_html = html_data["parse"]["text"].get("*", "")
        plain = strip_html(raw_html)
        if len(plain) > 100:
            doc = {
                "topic_id": topic_id,
                "source_type": "wikipedia",
                "source_url": f"https://en.wikipedia.org/wiki/{urllib.request.quote(raw_topic.replace(' ', '_'))}",
                "source_id": str(html_data["parse"].get("pageid", "")) + "_full",
                "title": html_data["parse"].get("title", raw_topic) + " (full)",
                "content_text": plain,
                "content_html": raw_html[:200000],
                "author": None,
                "score": None,
                "metadata": json.dumps({
                    "sections": [s.get("line", "") for s in html_data["parse"].get("sections", [])],
                    "categories": [c.get("*", "") for c in html_data["parse"].get("categories", [])],
                    "doc_subtype": "full_page",
                }),
                "content_hash": sha256(plain),
            }
            if upsert_source(cur, doc):
                stored += 1
                print(f"  ✓ Wikipedia full page ({len(plain)} chars)")
        else:
            print("  ✗ Wikipedia page too short")
    else:
        print("  ✗ No Wikipedia page found")

    time.sleep(1)

    # Reddit (via Pullpush archive API)
    print("  Searching Reddit...")
    posts = fetch_reddit(raw_topic) or []
    reddit_stored = 0
    for p in posts[:5]:
        if not p:
            continue
        text = f"{p.get('title', '')}\n\n{p.get('selftext', '')}".strip()
        if len(text) < 20:
            continue
        permalink = p.get("permalink", f"/r/{p.get('subreddit', '')}/comments/{p.get('id', '')}/")
        doc = {
            "topic_id": topic_id,
            "source_type": "reddit_post",
            "source_url": f"https://www.reddit.com{permalink}",
            "source_id": p.get("id", ""),
            "title": p.get("title", ""),
            "content_text": text[:30000],
            "content_html": None,
            "author": p.get("author", "[deleted]"),
            "score": p.get("score", 0),
            "metadata": json.dumps({
                "subreddit": p.get("subreddit", ""),
                "num_comments": p.get("num_comments", 0),
                "created_utc": p.get("created_utc"),
                "doc_subtype": "post",
            }),
            "content_hash": sha256(text),
        }
        if upsert_source(cur, doc):
            stored += 1
            reddit_stored += 1
    print(f"  ✓ {min(len(posts), 5)} Reddit posts checked, {reddit_stored} stored")

    time.sleep(6)  # Reddit rate limit

    # Mark ingested
    cur.execute("UPDATE topics SET status = 'ingested', updated_at = now() WHERE id = %s", (topic_id,))
    print(f"  Total: {stored} source documents stored")
    return stored


def seed_topics(cur) -> None:
    """Insert sample topics."""
    repo_dir = Path(__file__).resolve().parent.parent
    seed_file = repo_dir / "db" / "seed-topics.sql"
    if not seed_file.exists():
        print("Error: seed file not found", file=sys.stderr)
        sys.exit(1)
    with open(seed_file) as f:
        sql = f.read()
    cur.execute(sql)
    print("Seeded sample topics.")


def show_status(cur) -> None:
    """Print topic and source document counts."""
    cur.execute("SELECT status, COUNT(*) FROM topics GROUP BY status ORDER BY status")
    rows = cur.fetchall()
    print("\nTopics:")
    for status, count in rows:
        print(f"  {status}: {count}")

    cur.execute("SELECT source_type, COUNT(*) FROM source_documents GROUP BY source_type ORDER BY source_type")
    rows = cur.fetchall()
    print("\nSource documents:")
    if rows:
        for stype, count in rows:
            print(f"  {stype}: {count}")
    else:
        print("  (none)")

    cur.execute("SELECT COUNT(*) FROM source_documents")
    total = cur.fetchone()[0]
    print(f"\nTotal source documents: {total}")


def main() -> None:
    repo_dir = Path(__file__).resolve().parent.parent
    load_env(repo_dir)

    parser = argparse.ArgumentParser(description="Ingest sources for pending topics")
    parser.add_argument("--limit", type=int, default=0, help="Max topics to process (0 = all)")
    parser.add_argument("--topic", help="Process a specific topic slug")
    parser.add_argument("--seed", action="store_true", help="Seed sample topics before ingesting")
    parser.add_argument("--status", action="store_true", help="Show topic/source counts and exit")
    args = parser.parse_args()

    conn = get_db_conn()
    conn.autocommit = False
    cur = conn.cursor()

    try:
        if args.seed:
            seed_topics(cur)
            conn.commit()

        if args.status:
            show_status(cur)
            return

        # Load pending topics
        if args.topic:
            cur.execute("SELECT id, slug, raw_topic FROM topics WHERE slug = %s", (args.topic,))
        else:
            query = "SELECT id, slug, raw_topic FROM topics WHERE status = 'pending' ORDER BY CASE priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END, created_at ASC"
            if args.limit > 0:
                query += f" LIMIT {args.limit}"
            cur.execute(query)

        topics = cur.fetchall()
        if not topics:
            print("No pending topics found.")
            if not args.seed:
                print("Run with --seed to add sample topics.")
            return

        print(f"Processing {len(topics)} topic(s)...")
        total_docs = 0
        for topic_id, slug, raw_topic in topics:
            docs = ingest_topic(cur, topic_id, raw_topic, slug)
            total_docs += docs
            conn.commit()

        print(f"\n=== Done: {len(topics)} topics, {total_docs} source documents ===")

    except Exception as e:
        conn.rollback()
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()

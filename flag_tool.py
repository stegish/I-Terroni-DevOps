"""ITU-Minitwit tweet flagging tool.

Usage:
  flag_tool.py <tweet_id>...
  flag_tool.py -i
  flag_tool.py -h

Options:
  -h    Show this screen.
  -i    Dump all tweets and authors to STDOUT (CSV).
"""

import argparse
import csv
import sys

from db import SessionLocal
from models import Message


def dump_messages(session):
    writer = csv.writer(sys.stdout)
    writer.writerow(["message_id", "author_id", "text", "flagged"])
    for msg in session.query(Message).yield_per(1000):
        writer.writerow([msg.message_id, msg.author_id, msg.text, msg.flagged])


def flag_messages(session, ids):
    existing = {row[0] for row in session.query(Message.message_id).filter(Message.message_id.in_(ids)).all()}
    missing = [i for i in ids if i not in existing]

    if existing:
        session.query(Message).filter(Message.message_id.in_(existing)).update(
            {Message.flagged: 1}, synchronize_session=False
        )
        session.commit()
        for i in ids:
            if i in existing:
                print(f"Flagged entry: {i}")

    if missing:
        for i in missing:
            print(f"message_id not found: {i}", file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="ITU-Minitwit Tweet Flagging Tool",
        add_help=False,
    )
    parser.add_argument("-h", action="store_true", dest="help", help="Show this screen.")
    parser.add_argument("-i", action="store_true", dest="dump", help="Dump all tweets to STDOUT.")
    parser.add_argument("ids", nargs="*", type=int, help="Tweet IDs to flag.")
    args = parser.parse_args(argv)

    if args.help or (not args.dump and not args.ids):
        print(__doc__)
        return 0

    session = SessionLocal()
    try:
        if args.dump:
            dump_messages(session)
            return 0
        return flag_messages(session, args.ids)
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())

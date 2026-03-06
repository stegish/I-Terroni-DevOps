from db import get_db_session
from models import User, Follower

def report():
    db = get_db_session()
    total_users = db.query(User).count()
    total_follows = db.query(Follower).count()
    
    if total_users > 0:
        avg_followers = total_follows / total_users
    else:
        avg_followers = 0
        
    print("=== STATS ===")
    print(f"register users: {total_users}")
    print(f"average amount of followers a user has: {avg_followers:.2f}")
    print("================================")
    
    db.close()

if __name__ == '__main__':
    report()
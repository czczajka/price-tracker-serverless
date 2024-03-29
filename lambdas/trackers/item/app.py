import random
from datetime import datetime

item_to_track_name = "exampleItem"

def lambda_handler(event, context):
    val = random.randint(1, 10)  # Generate a random number between 1 and 10
    date = datetime.now().strftime("%Y-%m-%dT%H:%M")  # Get the current date and time

    rsp = {
        "name": item_to_track_name,
        "date": date,
        "value": val,
    }

    return rsp

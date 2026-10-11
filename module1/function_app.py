import azure.functions as func
import logging
import os
import json

from azure.identity import DefaultAzureCredential
from azure.communication.email import EmailClient


app = func.FunctionApp(
    http_auth_level=func.AuthLevel.ANONYMOUS
)


@app.route(
    route="ticket",
    methods=["POST"]
)
def ticket(req: func.HttpRequest) -> func.HttpResponse:

    logging.info("Novatrix: nytt ärende mottaget.")

    try:
        data = req.get_json()

        name = data.get("name")
        email = data.get("email")
        message = data.get("message")

        if not name or not email or not message:
            return func.HttpResponse(
                json.dumps({
                    "success": False,
                    "message": "Alla fält måste fyllas i."
                }),
                status_code=400,
                mimetype="application/json"
            )

        endpoint = os.environ["ACS_ENDPOINT"]
        sender_address = os.environ["SENDER_ADDRESS"]
        notification_email = os.environ["NOTIFICATION_EMAIL"]
        client_id = os.environ["AZURE_CLIENT_ID"]

        credential = DefaultAzureCredential(
            managed_identity_client_id=client_id
        )

        email_client = EmailClient(
            endpoint,
            credential
        )

        email_message = {
            "senderAddress": sender_address,

            "recipients": {
                "to": [
                    {
                        "address": notification_email
                    }
                ]
            },

            "content": {
                "subject": f"Nytt Novatrix-ärende från {name}",

                "plainText": f"""
Nytt kundtjänstärende

Namn:
{name}

E-post:
{email}

Meddelande:
{message}
"""
            },

            "replyTo": [
                {
                    "address": email
                }
            ]
        }

        poller = email_client.begin_send(email_message)
        result = poller.result()

        logging.info(
            "E-post skickad. Operation ID: %s",
            result.get("id")
        )

        return func.HttpResponse(
            json.dumps({
                "success": True,
                "message": "Ärendet har skickats."
            }),
            status_code=200,
            mimetype="application/json"
        )

    except ValueError:

        return func.HttpResponse(
            json.dumps({
                "success": False,
                "message": "Ogiltig JSON."
            }),
            status_code=400,
            mimetype="application/json"
        )

    except Exception:

        logging.exception(
            "Fel vid behandling av Novatrix-ärendet."
        )

        return func.HttpResponse(
            json.dumps({
                "success": False,
                "message": "Ett serverfel inträffade."
            }),
            status_code=500,
            mimetype="application/json"
        )

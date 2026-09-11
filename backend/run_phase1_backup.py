from flask import Flask
from flask_cors import CORS

from routes.login import login_bp
from routes.student import student_bp
from routes.attendance import attendance_bp

app = Flask(__name__)

CORS(app)

app.register_blueprint(login_bp)
app.register_blueprint(student_bp)
app.register_blueprint(attendance_bp)

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )
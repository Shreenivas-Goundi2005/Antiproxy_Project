from flask import Flask
from flask_cors import CORS


from routes.register import register_bp
from routes.login import login_bp
from routes.student import student_bp
from routes.attendance import attendance_bp
from routes.session import session_bp
from routes.faculty_register import faculty_register_bp
from routes.roster import roster_bp
from routes.admin import admin_bp

app = Flask(__name__)
app.config["SECRET_KEY"] = (
    "AntiProxy-Student-Attendance-2026-Change-This-Secret"
)

# Enable CORS
CORS(app)


# ==============================
# REGISTER ROUTES
# ==============================

app.register_blueprint(register_bp)
app.register_blueprint(login_bp)
app.register_blueprint(student_bp)
app.register_blueprint(attendance_bp)
app.register_blueprint(session_bp)
app.register_blueprint(faculty_register_bp)
app.register_blueprint(roster_bp)
app.register_blueprint(admin_bp)


# ==============================
# START SERVER
# ==============================

if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )
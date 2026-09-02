CREATE DATABASE IF NOT EXISTS antiproxy;

USE antiproxy;


-- =========================
-- USERS
-- =========================

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('student', 'faculty', 'admin') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- =========================
-- STUDENTS
-- =========================

CREATE TABLE students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    student_id VARCHAR(50) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    department VARCHAR(100),
    semester INT,
    face_registered BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);


-- =========================
-- FACULTY
-- =========================

CREATE TABLE faculty (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    faculty_id VARCHAR(50) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    department VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);


-- =========================
-- ATTENDANCE
-- =========================

CREATE TABLE attendance (
    id INT AUTO_INCREMENT PRIMARY KEY,

    student_id INT NOT NULL,

    attendance_date DATE NOT NULL,
    attendance_time TIME NOT NULL,

    status ENUM('present', 'absent', 'late') DEFAULT 'present',

    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),

    face_verified BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (student_id)
        REFERENCES students(id)
        ON DELETE CASCADE
);
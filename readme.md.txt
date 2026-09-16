# Project Grogu Backend

This repository contains the backend Web API for **Project Grogu**, built using **.NET 5**, **C#**, and **NeonDB (PostgreSQL)**. The architecture utilizes direct database communication via `Npgsql` and offloads core business logic to PostgreSQL stored functions.

---

**Tech Stack**
* **Framework:** .NET 5 Web API (C#)
* **Database:** NeonDB (Serverless PostgreSQL)
* **Data Access:** Npgsql (Direct SQL execution with stored procedures/functions)
* **Frontend Integration:** Linked with the Vercel-hosted client (`https://project-grogu-pi.vercel.app/`)

---

**Project Structure & Endpoints**

* **Auth (`/api/auth`)**
  * `POST /api/auth/signup`: Registers a new user (`Player`, `Studio`, or `Admin`).
  * `POST /api/auth/login`: Authenticates credentials against stored functions and returns user session details.
* **Players (`/api/players`)**
  * `POST /api/players/saveProfile`: Onboards or updates player profile details (age, experience, platforms, genres) linked by `userId`.
  * `PUT /api/players/{id}`: Partially updates player profile properties using SQL `COALESCE`.
  * `DELETE /api/players/{id}`: Deletes a player record.
  * `POST /api/players/apply`: Allows players to apply for playtests.
* **Studios (`/api/studios`)**
  * `GET /api/studios/{id}`: Retrieves studio details.
  * `PUT /api/studios/{id}`: Updates studio profile information.
  * `GET /api/studios/{id}/playtests`: Lists all playtests created by the studio.
  * `DELETE /api/studios/{id}`: Deletes a studio profile.
* **Playtests (`/api/playtests`)**
  * `POST /api/playtests`: Creates a new playtest session.
  * `GET /api/playtests/{id}`: Fetches playtest details.
  * `GET /api/playtests/{id}/applications`: Retrieves all player applications for a specific playtest.
* **Applications (`/api/applications`)**
  * `GET /api/applications/{id}`: Fetches application details.
  * `PUT /api/applications/{id}/status`: Updates application status (e.g., Pending, Approved, Rejected).
  * `DELETE /api/applications/{id}`: Removes an application.
* **Feedback (`/api/feedback`)**
  * `POST /api/feedback`: Submits player feedback and ratings for completed playtests.
  * `GET /api/feedback/{id}`: Fetches specific feedback.
  * `GET /api/feedback/playtest/{playtestId}`: Retrieves all feedback submitted for a playtest.
  * `DELETE /api/feedback/{id}`: Deletes a feedback entry.
* **Users (`/api/users`)**
  * `GET /api/users/{id}`: Fetches user info.
  * `PUT /api/users/{id}`: Updates user details.
  * `DELETE /api/users/{id}`: Deletes a user record.

---

**Configuration & Setup**

1. **Database Connection:** Update `appsettings.json` with your NeonDB connection string:
   ```json
   {
     "ConnectionStrings": {
       "NeonDBConnection": "Server=YOUR_HOST;Database=YOUR_DB;User Id=YOUR_USER;Password=YOUR_PASSWORD;SSL Mode=Require;"
     }
   }
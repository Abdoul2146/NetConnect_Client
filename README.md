#  NetConnect Client (Flutter)

**NetConnect Client** is the mobile front-end companion to the **NetConnect Server**. Built with **Flutter** (Dart), it enables real-time chat, group messaging, and file transfers through a sleek and user-friendly interface.


##  Features

- **User Authentication**  
  - Sign up and log in using secure credentials.

- **Real-Time Chat (via WebSockets)**  
  - Direct one-on-one messaging  
  - Group chat support  
  - Instant message delivery and UI updates

- **File Sharing**  
  - Upload and download files within chats

- **Responsive UI**  
  - Intuitive design suitable for mobile devices



##  Tech Stack

| Component     | Description                        |
|---------------|------------------------------------|
| **Language**  | Dart (Flutter SDK)                |
| **Client App**| Flutter-based mobile application |
| **Server**    | Communicates with FastAPI backend via REST & WebSockets |

##  Project Structure

NetConnect_Client/
- ├── screens/               # UI screens for authentication, chats, etc.
- ├── main.dart              # App entry point
- ├── server_config.dart     # Server URL and connection settings
- └── README.md              # Project documentation

## Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable)
* A running instance of **NetConnect Server**

### Setup & Run

1. **Clone the repository**

   git clone https://github.com/Abdoul2146/NetConnect_Client.git
   cd NetConnect_Client

2. **Configure server connection**

   * Open `server_config.dart`
   * Set the `baseUrl` and WebSocket endpoint to match your NetConnect Server

3. **Install dependencies**

   flutter pub get

4. **Run the app**

   * For Android/iOS:

     flutter run

   * Or open in your IDE (Android Studio, VS Code) and press **Run**


## Usage Flow

1. **Sign Up / Log In**
   Enter credentials to authenticate via the backend.

2. **Chat Interface**
   Select a user or group to start messaging in real-time.

3. **File Sharing**
   Attach files to chats and manage downloads seamlessly.


## Notes

* Ensure the server is running and accessible before launching the client.
* Consider adding features like push notifications or dark mode in future versions.
* Error handling (like connection drops) can be improved for better UX.


## Contributing

Contributions are welcome!

1. Fork the project
2. Create a feature branch (`feature/my-feature`)
3. Commit your changes (`git commit -m 'Add feature X'`)
4. Push and submit a pull request


## Author

**Abdulhakim Abdurrazak Sulaiman**
Creator of NetConnect — bringing seamless, real-time communication to your fingertips.


###  Screenshots
- Create Group
![Create_group](<Netconnnect Screenshot/create group.jpg>)

- Feed
![Feed](<Netconnnect Screenshot/feed.jpg>)

 - Home
 ![Home](<Netconnnect Screenshot/Home.jpg>)
 
- Inbox
 ![Inbox](<Netconnnect Screenshot/inbox.jpg>)
 
 - Profile
  ![Profile](<Netconnnect Screenshot/profile.jpg>)

- Settings
![settings](<Netconnnect Screenshot/settings.jpg>)

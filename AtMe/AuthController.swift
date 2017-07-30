//
//  AuthController.swift
//  AtMe
//
//  Created by Joel Rorseth on 2017-06-25.
//  Copyright © 2017 Joel Rorseth. All rights reserved.
//

import Firebase
import FirebaseCore


// Protocol to inform delegates of auth events
protocol AuthenticationDelegate {
    func userDidSignOut()
}


class AuthController {
    
    static var authenticationDelegate: AuthenticationDelegate?
    
    // Firebase References
    static var userInformationRef: DatabaseReference = Database.database().reference().child("userInformation")
    static var registeredUsernamesRef: DatabaseReference = Database.database().reference().child("registeredUsernames")
    
    private lazy var databaseManager = DatabaseController()
    
    
    // MARK: Account Management
    /**
     Asynchronously attempts to create an @Me account
     - parameters:
        - displayPicture: Firebase storage url for the users display picture (if set)
        - email: Email address
        - username: Username
        - firstName: First name
        - lastName: Last name
        - password: Password
        - completion: Callback that returns an Error object back to caller at completion
            - error: An Error object returned from the Auth Controller
            - uid: The UID assigned to the user upon successful account creation
     */
    public static func createAccount(email: String, firstName: String, lastName: String,
                              password: String, completion: @escaping ((Error?, String?) -> ()) ) {
    
        // If the username already exists, avoid creating user
        // Look this up asynchronously in Firebase, call completion callback when finished regardless of findings
        // Note: The must be done inside the observe block to properly update synchronously

        Auth.auth().createUser(withEmail: email, password: password, completion: { (user, error) in
            
            // Present backend errors to user when @Me does not catch them
            if let error = error {
                completion(error, user?.uid)
                return
            }
            
            // Add entry to usernames index and user info record
            self.userInformationRef.child((user?.uid)!).setValue(
                ["email" : email,
                 "firstName" : firstName,
                 "lastName" : lastName,
                 "notificationID": NotificationsController.currentDeviceNotificationID() ?? nil]
            )
            
            completion(error, user?.uid)
        })
    }
    
    
    /**
     Asynchronously attempts to sign in to an @Me account
     - parameters:
        - email: Email address
        - password: Password
        - completion: Callback that returns an Error object back to caller at completion
            - error: An Error object returned from the Auth Controller
            - configured: A boolean representing if the current user object could be configured (required)
     */
    public static func signIn(email: String, password: String, completion: @escaping ((Error?, Bool) -> ()) ) {
        
        // Let the auth object sign in the user with given credentials
        Auth.auth().signIn(withEmail: email, password: password) { (user, error) in
            
            // Call completion block with resulting error (hopefully nil when successful)
            if let error = error { completion(error, false); return }
            guard let user = user else { return }
            
            // Call database function to retrieve information about current user, and set the static current user object
            // The completion callback returns a bool indicating success, so return that value in this completion callback too!
            self.establishCurrentUser(user: user, completion: { configured in
                completion(error, configured)
            })
        }
    }
    
    
    /** Take the appropriate steps to sign the user out of the application. */
    public static func signOut() {
        
        AuthController.authenticationDelegate?.userDidSignOut()
        DatabaseController.clearCachedImages()
        DatabaseController.unsubscribeUserFromNotifications(uid: UserState.currentUser.uid)
        UserState.resetCurrentUser()
    }
    
    
    // MARK: User search and information retrieval
    /** Finds details for specified users, then returns a UserProfile for each found via a completion callback.
     - parameters:
     - results: A dictionary containing [username: uid] pairs for users
     - completion: A completion callback invoked each time details are found for a user
     profile: The UserProfile object representing and holding the details found for a specific user
     */
    public static func findDetailsForUsers(results: [String : String], completion: @escaping (UserProfile) -> Void) {
        
        // For each result found, observe the user's full name and pass back as a UserProfile object
        // Using this UserProfile, the table view can be updated with info by the caller!
        
        for (username, uid) in results {
            
            userInformationRef.child(uid).observeSingleEvent(of: DataEventType.value, with: { snapshot in
                
                // Read first and last name, pass back to caller using callback when done
                let first = snapshot.childSnapshot(forPath: "firstName").value as? String ?? ""
                let last = snapshot.childSnapshot(forPath: "lastName").value as? String ?? ""
                
                let user = UserProfile(name: first + " " + last, uid: uid, username: username)
                completion(user)
            })
        }
    }
    
    
    /** Performs a search using given string, and attempts to find a predefined number of users whom the user
     is most likely searching for. Please note that the search omits the current user.
     - parameters:
        - term: The term to search for and match usernames with
        - completion: A completion callback that fires when it has found all the results it can
            - results: An dictionary of (username, uid) pairs found in the search. Please note this may be empty if no results found!
     */
    public static func searchForUsers(term: String, completion: @escaping ([String : String]) -> ()) {
        
        registeredUsernamesRef.queryOrderedByKey().queryStarting(atValue: term).queryEnding(atValue: "\(term)\u{f8ff}")
            .queryLimited(toFirst: Constants.Limits.resultsCount).observeSingleEvent(of: DataEventType.value, with: { snapshot in
            
                // Parse results as dictionary of (username, uid) pairs
                if var results = snapshot.value as? [String : String] {
                    
                    // Never allow option to start conversation with yourself!!
                    results.removeValue(forKey: UserState.currentUser.username)
                    
                    // If and when found, pass results back to caller
                    completion(results)
                }
        })
    }
 
 
    /**
     Asynchronously determines if a given username has been taken in the current database
     - parameters:
        - username: Username to search for
        - completion: Callback that fires when function has finished
            - found: True if username was found in database, false otherwise
     */
    public static func usernameExists(username: String, completion: @escaping (Bool) -> ()) {
        
        registeredUsernamesRef.observeSingleEvent(of: DataEventType.value, with: { snapshot in
            
            if (snapshot.hasChild(username)) { completion(true) }
            else { completion(false) }
        })
    }
    
    
    // Current user maintenance
    /**
     Retrieve details for current user from the database. User must be authorized already.
     - parameters:
        - user: The current user, which should be authorized at this point
        - completion:Callback that fires when function has finished
            - configured: A boolean representing if the current user object could be configured (required)
     */
    public static func establishCurrentUser(user: User, completion: @escaping (Bool) -> ()) {
        
        // TODO: Change to take snapshot of only this user's info, use child(uid)
        // Look up information about the User, set the UserState.currentUser object properties
        self.userInformationRef.observeSingleEvent(of: DataEventType.value, with: { (snapshot) in
            
            // Important: Must be able to set ALL PROPERTIES of current user, else do not authorize!
            guard let email = user.email,
                let username = snapshot.childSnapshot(forPath: "\(user.uid)/username").value as? String,
                let first = snapshot.childSnapshot(forPath: "\(user.uid)/firstName").value as? String,
                let last = snapshot.childSnapshot(forPath: "\(user.uid)/lastName").value as? String
                else { completion(false); return }
            
            // Obtain current notification ID, update it 
            // Notification ID must always be optional, because users may not allow for it, and also because
            // notification id is removed from database at sign out (and will thus be empty at sign in)
            
            if let notificationID = NotificationsController.currentDeviceNotificationID() {
                self.userInformationRef.child("\(user.uid)/notificationID").setValue(notificationID)
                UserState.currentUser.notificationID = notificationID
            }
            
            // Set all properties of currentUser now that they have been unwrapped if needed
            UserState.currentUser.displayPicture = "\(user.uid)/\(user.uid).JPG"
            UserState.currentUser.email = email
            UserState.currentUser.name = first + " " + last
            UserState.currentUser.uid = user.uid
            UserState.currentUser.username = username
            
            completion(true)
        })
    }
    
    
    /**
     Writes current user's username into their information record and usernames registry in the database. This should
     never change after set, so only call when creating account.
     - parameters:
        - username: Username chosen by the current user
        - completion: Callback that is called upon successful completion
     */
    public static func setUsername(username: String, completion: (() -> ())) {
        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Set current user, update username field in userInformation and registeredUsernames
        UserState.currentUser.username = username
        userInformationRef.child("\(uid)/username").setValue(username)
        registeredUsernamesRef.child(username).setValue(uid)
        completion()
    }
    
    
    /**
     Writes the database storage path of an uploaded display picture to the current user's information record
     - parameters:
        - path: The path where the display picture has been successfully uploaded to
     */
    public static func setDisplayPicture(path: String) {
        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        print("Setting displayPict: \(path)")
        UserState.currentUser.displayPicture = path
        userInformationRef.child("\(uid)/displayPicture").setValue(path)
    }
    
    
    /** Attempt to change the current user's email, if possible. This will update Auth, the database and UserState.currentUser
     - parameters:
        - email: The email to change to
        - completion: A callback function that fires when email has been set, or discovers it cannot be done
            - error: An optional error that will be set only if an error occured and email was not changed
     */
    public static func changeEmailAddress(to email: String, completion: @escaping (Error?) -> Void) {
        
        // Use the Firebase Auth function to allow changes to internal auth records
        Auth.auth().currentUser?.updateEmail(to: email, completion: { error in
            
            if let error = error {
                print("Error changing email: \(error.localizedDescription)")
                completion(error)
                
            } else {
                
                // Update local and database email records, then callback
                self.userInformationRef.child(UserState.currentUser.uid).child("email").setValue(email)
                UserState.currentUser.email = email
                completion(nil)
            }
        })
    }
    
    
    /** Attempt to change the current user's password, but will never store or record it directly
     - parameters:
        - password: The new password requested
        - callback: Callback function that is called when Auth confirms it can or cannot perform change
            - error: An optional Error object that will hold information if and when request fails
     */
    public static func changePassword(password: String, callback: @escaping (Error?) -> Void) {
        
        // Use the Firebase Auth function to allow changes to internal auth records
        Auth.auth().currentUser?.updatePassword(to: password, completion: { error in
            
            if let error = error {
                
                print("Error changing password: \(error.localizedDescription)")
                callback(error)
                
            } else { callback(nil) }
        })
    }
    
    
    /** If possible, will set the attribute specified of the current user to the value provided. 
     - parameters:
        - attribute: Attribute to change
        - value: Value to set the attribute equal to
     */
    public static func changeCurrentUser(attribute: String, value: String) {
        userInformationRef.child(UserState.currentUser.uid).child("\(attribute)").setValue(value)
    }
}
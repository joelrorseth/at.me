//
//  ConvoViewController.swift
//  at.me
//
//  Created by Joel Rorseth on 2017-02-18.
//  Copyright © 2017 Joel Rorseth. All rights reserved.
//

import UIKit
import Firebase
import Kingfisher

// MARK: Input View for message bar
class ChatInputAccessoryView: UIInputView {
    
    private static let preferredHeight: CGFloat = 24.0
    @IBOutlet weak var expandingTextView: UITextView!
    
    // ==========================================
    // ==========================================
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: size.width, height: ChatInputAccessoryView.preferredHeight)
    }
    
    // ==========================================
    // Set the natural size to contain all contents in this view
    // ==========================================
    override var intrinsicContentSize: CGSize {
        var newSize = bounds.size
        
        if expandingTextView.bounds.size.height > 0.0 {
            newSize.height = expandingTextView.bounds.size.height + 20.0
        }
        
        if newSize.height < ChatInputAccessoryView.preferredHeight || newSize.height > 120.0 {
            newSize.height = ChatInputAccessoryView.preferredHeight
        }
        return newSize
    }
}


class ConvoViewController: UITableViewController, AlertController {
    
    // Firebase references
    var conversationRef: DatabaseReference?
    var messagesRef: DatabaseReference? = nil
    
    // Firebase handles
    private var messagesHandle: DatabaseHandle?
    private var activeMembersHandle: DatabaseHandle?
    
    internal let databaseManager = DatabaseController()
    
    // MARK: Storyboard
    @IBOutlet weak var chatInputAccessoryView: ChatInputAccessoryView!
    
    var observingMessages = false
    var messages: [Message] = []
    var notificationIDs: [String] = []
    
    
    
    // FIXME: This needs to be refactored, along with prepareForSegue in ChatList
    var convoId: String = "" {
        didSet {
            conversationRef = Database.database().reference().child("conversations/\(convoId)")
            messagesRef = Database.database().reference().child("conversations/\(convoId)/messages/")
            observeNotificationIDs()
            if (!observingMessages) { observeReceivedMessages(); observingMessages = true }
        }
    }
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = DateFormatter.Style.none
        formatter.timeStyle = DateFormatter.Style.short
        
        return formatter
    }()
    
    
    
    // Wrapper view controller for the custom input accessory view
    private let chatInputAccessoryViewController = UIInputViewController()
    
    override var inputAccessoryViewController: UIInputViewController? {
        // Ensure our input accessory view controller has it's input view set
        chatInputAccessoryView.translatesAutoresizingMaskIntoConstraints = false
        chatInputAccessoryViewController.inputView = chatInputAccessoryView
        
        // Return our custom input accessory view controller. You could also just return a UIView with
        // override func inputAccessoryView()
        return chatInputAccessoryViewController
    }
    
    // ==========================================
    // ==========================================
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    
    // MARK: IBAction methods
    // ==========================================
    // ==========================================
    @IBAction func didPressSend(_ sender: Any) {
        
        if (chatInputAccessoryView.expandingTextView.text == "" ||
            chatInputAccessoryView.expandingTextView.text == nil) { return }
        
        let message = Message(
            imageURL: nil,
            sender: UserState.currentUser.username,
            text: chatInputAccessoryView.expandingTextView.text!,
            timestamp: Date()
        )
        
        // Pass message along to be stored
        send(message: message)
        
        // Clear message text field and dismiss keyboard
        chatInputAccessoryView.expandingTextView.text = ""
        chatInputAccessoryView.expandingTextView.resignFirstResponder()
    }
    
    // ==========================================
    // ==========================================
    @IBAction func didPressCameraIcon(_ sender: Any) {
        
        // Create picker, and set this controller as delegate
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        
        // Call AlertController method to display ActionSheet allowing Camera or Photo Library selection
        // Use callback to set picker source type determined in the alert controller
        
        presentPhotoSelectionPrompt(completion: { (sourceType: UIImagePickerControllerSourceType) in
            
            picker.sourceType = sourceType
            self.present(picker, animated: true, completion: nil)
        })
    }
    
    // MARK: View
    // ==========================================
    // ==========================================
    override func viewDidLoad() {
        
        tableView.backgroundColor = UIColor.groupTableViewBackground
        tableView.allowsSelection = false
        
        addKeyboardObservers()
    }
    
    // ==========================================
    // ==========================================
    override func viewDidDisappear(_ animated: Bool) {
        
        
        if let handle = messagesHandle, let ref = messagesRef?.queryLimited(toLast: 25) {
            ref.removeObserver(withHandle: handle)
        } else { print("Error: No observer to remove") }
        
        if let handle = activeMembersHandle, let ref = conversationRef?.child("activeMembers") {
            ref.removeObserver(withHandle: handle)
        } else { print("Error: No observer to remove") }
        
        print("ConvoViewController did disappear. Database references deallocated.")
    }
    
    
    // MARK: Managing messages
    // ==========================================
    // ==========================================
    func send(message: Message) {
        
        // Write the message to Firebase
        let randomMessageId = messagesRef!.childByAutoId().key
        
        // Each message record (uniquely identified) will record sender and message text
        if let text = message.text {
            messagesRef?.child(randomMessageId).setValue(
                ["sender" : message.sender, "text" : text, "timestamp" : message.timestamp.timeIntervalSince1970]
            )
            
        } else if let imageURL = message.imageURL {
            messagesRef?.child(randomMessageId).setValue(
                ["imageURL": imageURL, "sender" : message.sender, "timestamp" : message.timestamp.timeIntervalSince1970]
            )
        }
        
        
        // Set timestamp for most recent conversation viewing
        // This is required to later determine if messages loaded have already been seen
        updateLastSeenTimestamp(convoID: convoId)
        
        // Ask NotificationController to send this message as a push notification
        for notificationID in notificationIDs {
            NotificationsController.send(to: notificationID, title: message.sender, message: message.text ?? "Picture message")
        }
    }
    
    // ==========================================
    // ==========================================
    private func addMessage(message: Message) {
        
        // Update data source
        messages.append(message)
        
        // Efficiently update by updating / inserting only the cells that need to be
        self.tableView.beginUpdates()
        self.tableView.insertRows(at: [IndexPath(row: messages.count - 1, section: 0)], with: .left)
        self.tableView.endUpdates()
        
        // TODO: Fix animation for initial message loading. Animation is kinda choppy
        print("Scrolling to row \(IndexPath.init(row: messages.count - 1, section: 0))")
        self.tableView.scrollToRow(at: IndexPath.init(row: messages.count - 1, section: 0) , at: .bottom, animated: false)
    }
    
    // ==========================================
    // ==========================================
    private func updateLastSeenTimestamp(convoID: String) {
        
        conversationRef?.child("lastSeen/\(UserState.currentUser.uid)").setValue(Date().timeIntervalSince1970)
    }
    
    
    // MARK: Observers
    // ==========================================
    // ==========================================
    private func observeReceivedMessages() {
        
        
        let messagesQuery = messagesRef?.queryLimited(toLast: 25)
        messagesQuery?.keepSynced(true)
        
        // This closure is triggered once for every existing record found, and for each record added here
        messagesHandle = messagesQuery?.observe(DataEventType.childAdded, with: { snapshot in
                        
            var imageURL: String?
            var text: String?
            
            // Unwrap picture message url or text message, can and must always be only one or the other
            if let imageURLValue = snapshot.childSnapshot(forPath: "imageURL").value as? String { imageURL = imageURLValue }
            if let textValue = snapshot.childSnapshot(forPath: "text").value as? String { text = textValue }
            
            let sender = snapshot.childSnapshot(forPath: "sender").value as! String
            let timestamp = Date.init(timeIntervalSince1970: snapshot.childSnapshot(forPath: "timestamp").value as! Double)
            
            // Because a new message has arrived, update the last message seen timestamp!
            self.updateLastSeenTimestamp(convoID: self.convoId)
            
            // Add message to local messages cache
            self.addMessage(message: Message(imageURL: imageURL, sender: sender, text: text, timestamp: timestamp))
        })
    }
    
    
    /** Observe all existing and new notification IDs for the current conversation. */
    private func observeNotificationIDs() {
        
        activeMembersHandle = conversationRef?.child("activeMembers").observe(DataEventType.childAdded, with: { snapshot in
            
            // Each member in activeMembers stores key-value pairs, specifically  (UID: notificationID) for active users
            // Firebase will take snapshot of each existing and new notificationID, store in property for push notifications later
            
            if let notificationID = snapshot.value as? String {
                
                // Avoid adding current user to notification list. We do not want notifications for our own messages
                if (notificationID != UserState.currentUser.notificationID) {
                    self.notificationIDs.append(notificationID)
                }
                
            } else { print("Error: Active member could not be converted into tuple during notificationID loading") }
        })
    }
    
    
    
    
    
    // MARK: Keyboard Handling
    /** Add gesture recognizer to track dismiss keyboard area */
    private func addKeyboardObservers() {
        
        // Add gesture recognizer to handle tapping outside of keyboard
        let dismissKeyboardTap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        self.tableView.addGestureRecognizer(dismissKeyboardTap)
    }
    
    
    /** Dismiss the custom keyboard (the input accessory) */
    func dismissKeyboard() {
        chatInputAccessoryView.expandingTextView.resignFirstResponder()
    }
    
    
    // MARK: Additional functions
    /**
     Obtains a timestamp of the current moment in time (described as the interval from 1970 until now)
     - returns: A TimeInterval object representing the time interval since 1970
     */
    func getCurrentTimestamp() -> TimeInterval {
        return Date().timeIntervalSince1970
    }
}


// MARK: UIImagePickerControllerDelegate
extension ConvoViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    // ==========================================
    // ==========================================
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        // TODO: Sending picture message bug, tapping message bar after makes it disapear
        
        if convoId == "" { dismiss(animated: true, completion: nil) }
        let path = "conversations/\(convoId)/images/\(Int(Date.timeIntervalSinceReferenceDate * 1000)).jpg"
        
        // Extract the image after editing, upload to database as Data object
        if let image = info[UIImagePickerControllerEditedImage] as? UIImage {
            if let data = convertImageToData(image: image) {
                
                databaseManager.uploadImage(data: data, to: path, completion: { (error) in
                    if let error = error {
                        print("AT.ME:: Error uploading picture message to Firebase. \(error.localizedDescription)")
                        return
                    }
                    
                    // Now that image has uploaded, officially send the message record to the database with storage URL
                    print("AT.ME:: Image uploaded successfully to \(path)")
                    self.send(message: Message(
                        imageURL: path,
                        sender: UserState.currentUser.username,
                        text: nil,
                        timestamp: Date()))
                })
                
            } else { print("AT.ME:: Error extracting image from source") }
        } else { print("AT.ME:: Error extracting edited UIImage from info dictionary") }
        
        dismiss(animated: true)
    }
    
    // ==========================================
    // ==========================================
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
    }
}

extension ConvoViewController: UITextViewDelegate {
    
    // ==========================================
    // ==========================================
    func textViewDidBeginEditing(_ textView: UITextView) {
        
        self.chatInputAccessoryView.expandingTextView.textColor = UIColor.darkGray
        
        // TODO: Test and refactor scrolling to clean up animation, avoid scrolling to inexistent rows
        if (messages.count != 0) {
            self.tableView.scrollToRow(at: IndexPath.init(row: messages.count - 1, section: 0) , at: .bottom, animated: true)
        }
            
        if (self.chatInputAccessoryView.expandingTextView.text == "Enter a message") {
            self.chatInputAccessoryView.expandingTextView.text = ""
        }
    }
    
    // ==========================================
    // ==========================================
    func textViewDidEndEditing(_ textView: UITextView) {
        self.chatInputAccessoryView.expandingTextView.textColor = UIColor.gray
        
        if (self.chatInputAccessoryView.expandingTextView.text == "") {
            self.chatInputAccessoryView.expandingTextView.text = "Enter a message"
        }
    }
}


// MARK: Table View Delegate
extension ConvoViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return messages.count }
    
    
    // ==========================================
    // ==========================================
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        // TODO: In the future, this cell configuration code should take place in the MessageCell
        // class. However, only so much can be done there since initializer will not know if message
        // is sent or received
        
        // Dequeue a custom cell for collection view
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.Storyboard.messageId, for: indexPath) as! MessageCell
        let message = messages[indexPath.row]
        
        // Clear message fields
        cell.messageImageView.image = nil
        cell.messageTextView.text = ""
        
        var messageSize = CGSize(width: 0, height: 0)
        var messageContentReference: UIView? = nil
        
        // Normal Text Message
        if let text = message.text {
            messageSize = sizeForString(text, maxWidth: tableView.bounds.width * 0.7, font: Constants.Fonts.regularText)
            messageContentReference = cell.messageTextView
            
            cell.messageTextView.text = message.text
        }
        
        // Picture Message
        if let imageURL = message.imageURL {
            
            messageSize = CGSize(width: 200, height: 200)
            messageContentReference = cell.messageImageView
            
            databaseManager.downloadImage(into: cell.messageImageView, from: imageURL, completion: { (error) in
                
                if let localError = error { print("AT.ME Error:: Did not recieve downloaded UIImage. \(localError)"); return }
                print("AT.ME:: Successfully loaded picture into message")
            })
        }

        
        if (message.sender == UserState.currentUser.username && messageContentReference != nil) { // Outgoing
            
            cell.bubbleView.backgroundColor = UIColor.white
            cell.messageTextView.textColor = UIColor.black
            
            messageContentReference?.frame = CGRect(x: tableView.bounds.width - messageSize.width - (MessageCell.horizontalInsetPadding + MessageCell.horizontalBubbleSpacing),
                                                    y: MessageCell.verticalInsetPadding + MessageCell.verticalBubbleSpacing,
                                                    width: messageSize.width,
                                                    height: messageSize.height)
            
            cell.bubbleView.frame = CGRect(x: tableView.bounds.width - messageSize.width - (MessageCell.horizontalInsetPadding + (2 * MessageCell.horizontalBubbleSpacing)),
                                           y: MessageCell.verticalInsetPadding,
                                           width: messageSize.width + (2 * MessageCell.horizontalBubbleSpacing),
                                           height: messageSize.height + (2 * MessageCell.verticalBubbleSpacing))
            
        } else { // Incoming
            
            cell.bubbleView.backgroundColor = Constants.Colors.primaryDark
            cell.messageTextView.textColor = UIColor.white
            
            messageContentReference?.frame = CGRect(x: MessageCell.horizontalInsetPadding + MessageCell.horizontalBubbleSpacing,
                                                    y: MessageCell.verticalInsetPadding + MessageCell.verticalBubbleSpacing,
                                                    width: messageSize.width,
                                                    height: messageSize.height)
            
            cell.bubbleView.frame = CGRect(x: MessageCell.horizontalInsetPadding,
                                           y: MessageCell.verticalInsetPadding,
                                           width: messageSize.width + (2 * MessageCell.horizontalBubbleSpacing),
                                           height: messageSize.height + (2 * MessageCell.verticalBubbleSpacing))
        }
        
        return cell
    }
    
    // ==========================================
    // ==========================================
    func sizeForString(_ string: String, maxWidth: CGFloat, font: UIFont) -> CGSize {
        
        let storage = NSTextStorage(string: string)
        let container = NSTextContainer(size: CGSize(width: maxWidth, height: 10000))
        let manager = NSLayoutManager()
        
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        
        storage.addAttribute(NSFontAttributeName, value: font, range: NSMakeRange(0, storage.length))
        container.lineFragmentPadding = 0.0
        
        manager.glyphRange(for: container)
        let size = manager.usedRect(for: container).size
        
        //print("Size = \(size) > \t\t\"\(string)\"")
        return size
    }
    
    // ==========================================
    // ==========================================
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        if let text = messages[indexPath.row].text {
            return sizeForString(text, maxWidth: tableView.bounds.width * 0.7, font: Constants.Fonts.regularText).height + (2 * MessageCell.verticalBubbleSpacing) + (2 * MessageCell.verticalInsetPadding)
        }
        
        if let _ = messages[indexPath.row].imageURL {
            return 200 + (2 * MessageCell.verticalBubbleSpacing) + (2 * MessageCell.verticalInsetPadding)
            
        }
        
        return 0
    }
}

//
//  MessageCell.swift
//  at.me
//
//  Created by Joel Rorseth on 2017-02-20.
//  Copyright © 2017 Joel Rorseth. All rights reserved.
//

import UIKit

class MessageCell: UICollectionViewCell {
    
    public static let horizontalBubblePadding: CGFloat = 8
    public static let verticalBubblePadding: CGFloat = 8
    
    // MARK: Lazy properties for UI message elements
    // ==========================================
    // ==========================================
    // UIView for outside chat bubble
    let bubbleView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        return view
    }()
    
    
    // Text view for message content
    let messageTextView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: CGFloat(Constants.Text.defaultTextSize))
        textView.isEditable = false
        textView.backgroundColor = UIColor.clear
        return textView
    }()
    
    // TODO: Figure out a better way to clip to a mask (bubbleView)
    let messageImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = UIViewContentMode.scaleAspectFit
        imageView.layer.cornerRadius = 12
        imageView.layer.masksToBounds = true
        return imageView
    }()
    
    
    // MARK: Initializers
    // ==========================================
    // Seems to be called after view is loaded
    // ==========================================
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupViews()
    }
    
    // ==========================================
    // Seems to be called when view is first loaded
    // ==========================================
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        setupViews()
    }
    
    // ==========================================
    // ==========================================
    func setupViews() {
        
        // The message and bubble view are subviews of cell
        //self.layer.masksToBounds = true
        self.addSubview(bubbleView)
        self.addSubview(messageTextView)
        self.addSubview(messageImageView)
    }
}

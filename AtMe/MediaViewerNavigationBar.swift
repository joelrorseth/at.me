//
//  MediaViewerNavigationBar.swift
//  AtMe
//
//  Created by Joel Rorseth on 2018-05-21.
//  Copyright © 2018 Joel Rorseth. All rights reserved.
//

import UIKit


// MARK: MediaViewerBarDelegate
// The UINavigationBar subclass will send the delegate updates by calling these methods
protocol MediaViewerBarDelegate {
  func didPressDone()
  func didPressSave()
}


class MediaViewerNavigationBar: UINavigationBar {
  
  // Delegate to respond to nav bar events
  var viewerDelegate: MediaViewerBarDelegate?
  
  // Initializer
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    setup()
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // Primary setup -- initialize views and selectors
  private func setup() {
    
    // Establish transparent background
    self.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
    self.shadowImage = UIImage()
    self.isTranslucent = true
    self.backgroundColor = UIColor.clear
    self.translatesAutoresizingMaskIntoConstraints = false
    
    // Establish the contents of the bar
    let navigationItem = UINavigationItem()
    let doneButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.done,
                                     target: self, action: #selector(doneSelector))
    let saveButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.save,
                                     target: self, action: #selector(saveSelector))
    
    doneButton.tintColor = Constants.Colors.whiteText
    saveButton.tintColor = Constants.Colors.whiteText
    
    // Set the bar items
    navigationItem.leftBarButtonItem = doneButton
    navigationItem.rightBarButtonItem = saveButton
    
    self.items = [navigationItem]
  }
  
  @objc private func doneSelector() {
    viewerDelegate?.didPressDone()
  }
  
  @objc private func saveSelector() {
    viewerDelegate?.didPressSave()
  }
}

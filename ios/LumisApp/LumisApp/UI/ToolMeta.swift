import Foundation

/// Human label + SF Symbol for a backend tool. Used by result + history cards.
func toolMeta(_ tool: String?) -> (label: String, symbol: String) {
    switch tool {
    case "notes.create_from_image", "notes.append_to_note", "notes.list_notes":
        return ("Apple Notes", "note.text")
    case "numbers.create_spreadsheet", "numbers.add_expense",
         "numbers.read_sheet", "numbers.edit_cell":
        return ("Apple Numbers", "tablecells.fill")
    case "slides.create_presentation":                       return ("Google Slides", "rectangle.on.rectangle.angled")
    case "gmail.draft_email", "gmail.reply_draft":           return ("Gmail", "envelope.fill")
    case "gmail.read_inbox", "gmail.read_email":             return ("Inbox", "tray.fill")
    case "browser.open_url", "browser.read_page", "browser.fill_form":
        return ("Chrome", "safari.fill")
    case "media.open_apple_music":                           return ("Apple Music", "music.note")
    case "media.open_spotify", "media.play_pause",
         "media.next_track", "media.previous_track":
        return ("Music", "music.note")
    case "ios.create_reminder":                              return ("Reminder", "checklist")
    case "ios.create_note":                                  return ("Note", "note.text")
    case "ios.open_maps":                                    return ("Maps", "map.fill")
    case "ios.send_message_draft":                           return ("Messages", "message.fill")
    case "calendar.create_event", "calendar.read_today",
         "calendar.read_week", "calendar.find_free_time":    return ("Calendar", "calendar")
    case "reminders.add_item", "reminders.read_list",
         "reminders.complete_item":                          return ("Reminders", "checklist")
    case "contacts.find":                                    return ("Contacts", "person.crop.circle")
    case "web.search", "web.fetch_page", "web.research":     return ("Web", "globe")
    default:                                                 return (tool ?? "Done", "checkmark.seal.fill")
    }
}

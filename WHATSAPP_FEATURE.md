# WhatsApp Voice Message Feature

## Overview

This feature allows RoadMate users to send WhatsApp messages via voice commands while driving. Users can speak messages, select recipients from saved contacts, and optionally attach photos from their camera roll.

## Implementation Summary

### Files Created

1. **`lib/models/whatsapp_contact.dart`** - Contact model with flexible parsing
   - Supports multiple memory formats: "mom's whatsapp is +1234567890", "Alice WhatsApp: +44123456789", etc.
   - Automatically cleans phone numbers (removes spaces, dashes, parentheses)
   - Adds country code (+1) to 10-digit US numbers
   - Capitalizes contact names

2. **`lib/services/whatsapp_service.dart`** - Core WhatsApp integration service
   - `toolSendWhatsAppMessage()` - Main tool handler
   - `_findContact()` - Search memory for WhatsApp contacts
   - `_getSenderName()` - Read sender name from preferences
   - `_sendTextOnly()` - URL scheme for text messages
   - `_sendWithPhoto()` - Share intent for photo + text
   - `_findPhoto()` - Search photos by location/time

3. **`test/whatsapp_contact_test.dart`** - Unit tests for contact parsing
   - Tests for all memory format variations
   - Tests for phone number cleaning
   - Tests for error handling

### Files Modified

4. **`lib/config.dart`**
   - Added `send_whatsapp_message` tool definition
   - Updated system prompt with WhatsApp instructions

5. **`lib/main.dart`**
   - Registered `send_whatsapp_message` tool handler
   - Added import for `WhatsAppService`

6. **`pubspec.yaml`**
   - Added `whatsapp_share2: ^2.0.0` dependency

7. **`ios/Runner/Info.plist`**
   - Added `LSApplicationQueriesSchemes` with `whatsapp` URL scheme

## Usage

### Saving Contacts

Users must first save WhatsApp contacts to memory:

```
"Remember mom's WhatsApp is +1-408-555-1234"
"Remember Alice WhatsApp: +44-123-456-789"
"Remember whatsapp for Bob: +1 (650) 555-0123"
```

The system supports flexible parsing of various formats.

### Sending Messages

**Text-only message:**
```
"Send Alice a WhatsApp saying hello from RoadMate"
```

**With sender name (if configured in preferences):**
```
"Send Alice a WhatsApp from me saying I'm running late"
```

**With photo:**
```
"Send Alice a WhatsApp with a photo from Paris saying look at this"
```

**With photo by time:**
```
"Send Bob a WhatsApp with a photo from yesterday saying remember this?"
```

### How It Works

**Text-only messages:**
1. User speaks command
2. Assistant calls `send_whatsapp_message` tool
3. Service looks up contact in memory
4. Service opens WhatsApp with pre-filled message to specific contact
5. User taps "Send" in WhatsApp to confirm

**Messages with photos:**
1. User speaks command with photo request
2. Assistant calls `send_whatsapp_message` tool
3. Service looks up contact in memory
4. Service finds photo if requested (via PhotoIndexService)
5. Service opens system share sheet with photo and message
6. User selects WhatsApp from share sheet
7. User selects recipient in WhatsApp and taps Send

**Note:** Due to platform security restrictions:
- Text-only messages can pre-select the recipient in WhatsApp
- Messages with photos use the system share sheet and require manual recipient selection

## Technical Details

### Contact Storage

Contacts are stored in the existing `MemoryStore` (plain text file). This:
- Keeps the architecture consistent
- Avoids device contacts permission requirements
- Gives users full control over shared contacts
- Works across platforms

### Phone Number Handling

The system automatically:
- Cleans formatting (spaces, dashes, parentheses)
- Adds +1 country code to 10-digit US numbers
- Preserves international format for other countries

### Photo Integration

Leverages existing `PhotoIndexService`:
- Natural language search: "photo from Paris", "photo from last week"
- Location-based search using GPS metadata
- Time-based search using photo timestamps
- Falls back to text-only if no photo found

### WhatsApp Integration

Uses two methods:
1. **Text-only**: `whatsapp://send?phone=X&text=Y` URL scheme (fast, native, pre-selects recipient)
2. **With photo**: `share_plus` package using system share sheet (user selects WhatsApp and recipient)

Fallback to web link (`https://wa.me/`) if WhatsApp app not found.

## Testing

### Unit Tests

Run contact parsing tests:
```bash
flutter test test/whatsapp_contact_test.dart
```

All 9 tests pass, covering:
- Multiple memory format variations
- Phone number cleaning
- Country code handling
- Error cases

### Manual Testing

1. **Save and send text:**
   - "Remember Alice's WhatsApp is +1-408-555-1234"
   - Verify memory contains contact
   - "Send Alice a WhatsApp saying hello from RoadMate"
   - Verify WhatsApp opens with correct recipient and message

2. **Send with sender name:**
   - Edit `preferences.txt`: Add "sender_name_for_whatsapp: John"
   - "Send Alice a WhatsApp from me saying I'm running late"
   - Verify message includes "From John: I'm running late"

3. **Send with photo:**
   - Ensure camera roll has photos with GPS metadata
   - "Send Alice a WhatsApp with a photo from Paris saying look at this"
   - Verify WhatsApp opens with photo attached

4. **Contact not found:**
   - "Send Bob a WhatsApp saying hi" (Bob not in memory)
   - Verify error message suggests saving contact first

5. **Photo not found (fallback):**
   - "Send Alice a WhatsApp with a photo from Tokyo last year"
   - No matching photos
   - Verify WhatsApp opens with text only

## Dependencies

- `share_plus: ^10.1.3` - System share sheet for photo attachments
- `url_launcher` (existing) - WhatsApp URL scheme handling for text-only messages
- `photo_manager` (existing) - Photo file access
- `shared_preferences` (existing) - Not used in this feature

No additional permissions required (WhatsApp URL scheme and share sheet handled automatically by OS).

## Error Handling

The service handles:
- Contact not found → Suggests saving contact first
- Invalid phone number → Graceful error message
- Photo access denied → Falls back to text-only
- WhatsApp not installed → Clear error message

All errors return user-friendly messages through the tool response.

## Future Enhancements

1. Contact management UI in settings (view/edit WhatsApp contacts)
2. Support multiple photos in single message
3. WhatsApp Business integration
4. Contact suggestions based on message history
5. Voice-to-voice WhatsApp calls integration

## Architecture Notes

This implementation follows RoadMate's established patterns:
- Tool definition in `config.dart`
- Service implementation in `services/`
- Tool registration in `main.dart`
- Reuse of existing services (MemoryStore, PhotoIndexService)
- No external state management
- Privacy-focused (no device contacts access)

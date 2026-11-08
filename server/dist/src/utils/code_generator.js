import { CONFIG } from "../config/config.js";
export function generateRoomCode(isCodeTaken) {
    const chars = CONFIG.ROOM_CODE_ALPHABET;
    for (let attempt = 0; attempt < 256; attempt++) {
        let code = "";
        for (let i = 0; i < CONFIG.ROOM_CODE_LENGTH; i++) {
            const idx = Math.floor(Math.random() * chars.length);
            code += chars[idx];
        }
        if (!isCodeTaken(code)) {
            return code;
        }
    }
    return "";
}
export function normalizeRoomCode(code) {
    return code.trim().toUpperCase();
}
export function isValidRoomCode(code) {
    if (code.length !== CONFIG.ROOM_CODE_LENGTH) {
        return false;
    }
    for (const c of code) {
        if (!CONFIG.ROOM_CODE_ALPHABET.includes(c)) {
            return false;
        }
    }
    return true;
}

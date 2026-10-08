// A failure with an HTTP status and a short code the game can switch on.
export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

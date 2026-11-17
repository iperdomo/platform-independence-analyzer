Office.onReady(() => {
  void fetch("https://graph.microsoft.com/v1.0/me/sendMail", { method: "POST" });
});

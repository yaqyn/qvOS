const notify = (title, message = '') => chrome.notifications.create({
  type: 'basic',
  iconUrl: 'icon.png',
  title,
  message
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== 'copy-url') return;

  try {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    if (!Number.isInteger(tab?.id)) throw new Error('No active browser tab');

    await chrome.scripting.executeScript({
      target: {tabId: tab.id},
      func: () => navigator.clipboard.writeText(window.location.href)
    });
    await notify('URL copied to clipboard');
  } catch (error) {
    console.error('qvOS Copy URL failed', error);
    await notify('Could not copy URL', 'The active page does not allow copying.');
  }
});

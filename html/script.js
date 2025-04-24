// html/script.js
// IMPORTANT: Set this variable to your EXACT resource folder name
const resourceName = "CR-VehicleRadio";

// === DOM Elements ===
const container = document.getElementById("container");
const urlInput = document.getElementById("url-input"); // Main URL input/display
const volumeSlider = document.getElementById("volume-slider");
const volumeValue = document.getElementById("volume-value");
const playButton = document.getElementById("play-button");
const stopButton = document.getElementById("stop-button");
const closeButton = document.getElementById("close-button");
const statusText = document.getElementById("status-text");

const favoritesList = document.getElementById("favorites-list");
const favNicknameInput = document.getElementById("fav-nickname-input"); // Input for saving nickname
const favUrlInput = document.getElementById("fav-url-input"); // Input for saving URL
const saveButton = document.getElementById("save-button");

// === Helper Functions ===

// Function to send data to Lua NUI callbacks
async function postData(event, data = {}) {
  const url = `https://${resourceName}/${event}`;
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=UTF-8",
      },
      body: JSON.stringify(data),
    });
    // Check if the response is ok (status in the range 200-299)
    if (!response.ok) {
      // Log the response status text if available
      console.error(
        `NUI Error Response for [${event}]: ${response.status} ${response.statusText}`
      );
      // Try to parse the response body for more details if available
      try {
        const errorBody = await response.json();
        console.error("NUI Error Body:", errorBody);
        return errorBody; // Return error details if parsed
      } catch (e) {
        // If response body cannot be parsed as JSON, return basic error
        return { ok: false, error: `HTTP error ${response.status}` };
      }
    }
    // Attempt to parse JSON, handle cases where response might be empty or not JSON
    const responseData = await response
      .json()
      .catch(() => ({ ok: true, response: "empty" })); // Handle empty/non-JSON responses gracefully
    // console.log(`NUI Response for [${event}]:`, responseData); // Optional: Debug NUI responses
    return responseData;
  } catch (error) {
    console.error(`Failed to send NUI message [${event}] to ${url}:`, error);
    return { ok: false, error: error.message || "Unknown fetch error" };
  }
}

function updateVolumeDisplay(value) {
  volumeValue.textContent = `${Math.round(value * 100)}%`;
}

function updateStatus(playing, url = null) {
  statusText.textContent = playing ? "Playing" : "Stopped";
  if (playing && url) {
    urlInput.value = url; // Update input field with the playing URL
    urlInput.title = url; // Show full URL on hover
  } else if (!playing) {
    // Decide if you want to clear the URL input when stopped
    // urlInput.value = '';
    // urlInput.title = '';
  }
}

function populateFavorites(favorites) {
  favoritesList.innerHTML = ""; // Clear current list
  if (!favorites || Object.keys(favorites).length === 0) {
    favoritesList.innerHTML = "<p>No favorites saved.</p>";
    return;
  }

  // Sort favorites by nickname for consistent display (case-insensitive)
  const sortedFavIds = Object.keys(favorites).sort((a, b) => {
    // Handle potential missing nicknames gracefully during sort
    const nameA = favorites[a]?.nickname?.toLowerCase() || "";
    const nameB = favorites[b]?.nickname?.toLowerCase() || "";
    return nameA.localeCompare(nameB);
  });

  // Use sortedFavIds to iterate
  for (const favUUID of sortedFavIds) {
    const favData = favorites[favUUID];
    // Make sure favData and its properties exist before proceeding
    if (
      !favData ||
      typeof favData.nickname === "undefined" ||
      typeof favData.url === "undefined"
    ) {
      console.warn(`Skipping malformed favorite entry with UUID: ${favUUID}`);
      continue; // Skip this entry
    }

    const div = document.createElement("div");
    div.classList.add("favorite-item");
    // Store data on the element itself
    div.dataset.favUuid = favUUID; // Store the unique ID
    div.dataset.url = favData.url; // Store the URL

    const nameSpan = document.createElement("span");
    nameSpan.classList.add("fav-name");
    nameSpan.textContent = favData.nickname || "(No Nickname)"; // Display nickname
    nameSpan.title = favData.url || "No URL"; // Show URL on hover

    // Click on favorite name puts URL in the main input box
    nameSpan.addEventListener("click", (event) => {
      const clickedItem = event.target.closest(".favorite-item");
      const urlToPlay = clickedItem.dataset.url;
      if (urlToPlay) {
        urlInput.value = urlToPlay; // Put URL in the main input
        urlInput.title = urlToPlay;
        console.log(
          `Selected favorite '${favData.nickname}', URL: ${urlToPlay}`
        );
        // Optional: Automatically play when favorite is clicked
        // playButton.click();
      } else {
        console.warn("Clicked favorite item missing URL data:", clickedItem);
      }
    });

    const deleteBtn = document.createElement("button");
    deleteBtn.classList.add("delete-fav-button");
    deleteBtn.textContent = "X";
    deleteBtn.title = `Delete Favorite: ${favData.nickname}`; // Tooltip

    // Click delete button sends delete request
    deleteBtn.addEventListener("click", (event) => {
      event.stopPropagation(); // Prevent triggering the nameSpan click
      const itemToDelete = event.target.closest(".favorite-item");
      const uuidToDelete = itemToDelete.dataset.favUuid;
      const nicknameToDelete =
        itemToDelete.querySelector(".fav-name").textContent; // Get nickname for confirmation

      if (
        uuidToDelete &&
        confirm(
          `Are you sure you want to delete favorite "${nicknameToDelete}"?`
        )
      ) {
        console.log(`Requesting delete for favorite UUID: ${uuidToDelete}`);
        postData("deleteFavorite", { favUUID: uuidToDelete }); // Send UUID
      } else if (!uuidToDelete) {
        console.error("Could not find UUID to delete for item:", itemToDelete);
      }
    });

    div.appendChild(nameSpan);
    div.appendChild(deleteBtn);
    favoritesList.appendChild(div);
  }
}

// === Event Listeners ===

// NUI Message Listener (from Lua)
window.addEventListener("message", (event) => {
  const data = event.data;
  // console.log("NUI Message Received:", data); // General debug for incoming messages

  if (!data || !data.type) {
    console.warn("Received NUI message without type:", data);
    return;
  }

  switch (data.type) {
    case "ui":
      container.style.display = data.display ? "block" : "none";
      // Reset save form when UI opens?
      if (data.display) {
        favNicknameInput.value = "";
        favUrlInput.value = ""; // Clear save inputs on open
        console.log("UI opened by Lua");
      } else {
        console.log("UI closed by Lua");
      }
      break;
    case "updateState":
      // console.log("Received state update:", data.state);
      const state = data.state || {}; // Ensure state exists
      updateStatus(state.playing || false, state.url || null);
      if (typeof state.volume === "number") {
        // Check if volume is a valid number
        volumeSlider.value = state.volume;
        updateVolumeDisplay(state.volume);
      }
      break;
    case "favorites":
      // console.log("Received favorites list:", data.favorites);
      populateFavorites(data.favorites || {});
      break;
    default:
      console.warn(`Received unknown NUI message type: ${data.type}`, data);
      break;
  }
});

// Control Listeners
playButton.addEventListener("click", () => {
  const url = urlInput.value.trim(); // Play whatever URL is in the input
  const volume = parseFloat(volumeSlider.value);
  if (url && url.startsWith("http")) {
    // Basic check
    console.log(`Play button clicked. URL: ${url}, Volume: ${volume}`);
    postData("play", { url: url, volume: volume });
  } else {
    alert(
      "Please enter a valid Stream URL starting with http(s):// or click a favorite."
    );
    console.warn(`Play button clicked with invalid URL: ${url}`);
  }
});

stopButton.addEventListener("click", () => {
  console.log("Stop button clicked.");
  postData("stop");
});

volumeSlider.addEventListener("input", (event) => {
  // Update display continuously while sliding
  updateVolumeDisplay(event.target.value);
});

volumeSlider.addEventListener("change", (event) => {
  // Send volume update to Lua only when the user releases the slider
  const newVolume = parseFloat(event.target.value);
  console.log(`Volume slider changed. New value: ${newVolume}`);
  postData("setVolume", { volume: newVolume });
});

// Save Button Logic
saveButton.addEventListener("click", () => {
  const nickname = favNicknameInput.value.trim();
  const url = favUrlInput.value.trim(); // Use the dedicated URL input for saving

  if (nickname && url && url.startsWith("http")) {
    console.log(`Save button clicked. Nickname: ${nickname}, URL: ${url}`);
    postData("saveFavorite", { nickname: nickname, url: url });
    // Clear inputs after attempting save
    favNicknameInput.value = "";
    favUrlInput.value = "";
  } else {
    alert(
      "Please enter a valid Nickname and a valid Stream URL (starting with http:// or https://) to save."
    );
    console.warn(
      `Save button clicked with invalid input. Nickname: '${nickname}', URL: '${url}'`
    );
  }
});

closeButton.addEventListener("click", () => {
  console.log("Close button clicked.");
  postData("close");
});

// Close UI with Escape key
document.addEventListener("keydown", (event) => {
  // Check if the container is visible before closing with Escape
  if (event.key === "Escape" && container.style.display !== "none") {
    console.log("Escape key pressed, closing UI.");
    postData("close");
  }
});

// Initial setup when the script loads
console.log("Radio UI script loaded.");
updateVolumeDisplay(volumeSlider.value); // Set initial volume display

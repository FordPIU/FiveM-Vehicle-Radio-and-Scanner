// html/script.js
const resourceName = "CR-VehicleRadio";

// === DOM Elements ===
const container = document.getElementById("container");
const urlInput = document.getElementById("url-input");
const volumeSlider = document.getElementById("volume-slider");
const volumeValue = document.getElementById("volume-value");
const playButton = document.getElementById("play-button");
const stopButton = document.getElementById("stop-button");
const closeButton = document.getElementById("close-button");
const statusText = document.getElementById("status-text");
const playingUrl = document.getElementById("playing-url");
const favoritesList = document.getElementById("favorites-list");
const favIdInput = document.getElementById("fav-id-input");
const saveButton = document.getElementById("save-button");

// === Helper Functions ===
async function postData(event, data = {}) {
  try {
    const response = await fetch(`https://${resourceName}/${event}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=UTF-8",
      },
      body: JSON.stringify(data),
    });
    return await response.json(); // NUI callbacks usually return 'ok' or an object
  } catch (error) {
    console.error("Failed to send NUI message:", event, error);
    return { ok: false, error: error.message };
  }
}

function updateVolumeDisplay(value) {
  volumeValue.textContent = `${Math.round(value * 100)}%`;
}

function updateStatus(playing, url) {
  statusText.textContent = playing ? "Playing" : "Stopped";
  playingUrl.textContent = playing ? url : "N/A";
  urlInput.value = playing ? url : ""; // Update input field if playing
}

function populateFavorites(favorites) {
  favoritesList.innerHTML = ""; // Clear current list
  if (Object.keys(favorites).length === 0) {
    favoritesList.innerHTML = "<p>No favorites saved.</p>";
    return;
  }

  for (const [id, url] of Object.entries(favorites)) {
    const div = document.createElement("div");
    div.classList.add("favorite-item");

    const nameSpan = document.createElement("span");
    nameSpan.classList.add("fav-name");
    nameSpan.textContent = id;
    nameSpan.title = url; // Show URL on hover
    nameSpan.addEventListener("click", () => {
      urlInput.value = id; // Put favorite ID in input for playing
    });

    const deleteBtn = document.createElement("button");
    deleteBtn.classList.add("delete-fav-button");
    deleteBtn.textContent = "X";
    deleteBtn.addEventListener("click", (event) => {
      event.stopPropagation(); // Prevent triggering the nameSpan click
      if (confirm(`Delete favorite "${id}"?`)) {
        postData("deleteFavorite", { favId: id });
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

  switch (data.type) {
    case "ui":
      container.style.display = data.display ? "block" : "none";
      break;
    case "updateState":
      const state = data.state;
      updateStatus(state.playing, state.url);
      if (state.volume !== undefined) {
        volumeSlider.value = state.volume;
        updateVolumeDisplay(state.volume);
      }
      break;
    case "favorites":
      populateFavorites(data.favorites || {});
      break;
  }
});

// Control Listeners
playButton.addEventListener("click", () => {
  const url = urlInput.value.trim();
  const volume = parseFloat(volumeSlider.value);
  if (url) {
    postData("play", { url: url, volume: volume });
  } else {
    alert("Please enter a URL or Favorite ID.");
  }
});

stopButton.addEventListener("click", () => {
  postData("stop");
});

volumeSlider.addEventListener("input", (event) => {
  updateVolumeDisplay(event.target.value);
});

volumeSlider.addEventListener("change", (event) => {
  // Only send volume update when user releases slider
  postData("setVolume", { volume: parseFloat(event.target.value) });
});

saveButton.addEventListener("click", () => {
  const favId = favIdInput.value.trim();
  const url = urlInput.value.trim(); // Save the URL currently in the main input
  if (favId && url) {
    postData("saveFavorite", { favId: favId, url: url });
    favIdInput.value = ""; // Clear save ID input
  } else {
    alert(
      "Please enter both a Favorite ID to save as, and a URL in the main input field."
    );
  }
});

closeButton.addEventListener("click", () => {
  postData("close");
});

// Close UI with Escape key
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    postData("close");
  }
});

// Initial setup
updateVolumeDisplay(volumeSlider.value);

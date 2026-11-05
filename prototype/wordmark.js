const params = new URLSearchParams(location.search);
const root = document.documentElement;
const scheme = matchMedia('(prefers-color-scheme: dark)');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const identity = document.querySelector('.identity');
const word = document.querySelector('.wordmark');
const stroke = document.querySelector('.shaving path');
const hint = document.querySelector('.command-hint');
let theme = ['light', 'dark'].includes(params.get('theme')) ? params.get('theme') : 'system';
let opening = [];

function appearance() {
  root.dataset.theme = theme === 'system' ? (scheme.matches ? 'dark' : 'light') : theme;
  document.querySelector('#appearance').textContent = theme[0].toUpperCase() + theme.slice(1);
}

function finishOpening() {
  opening.forEach(animation => animation.cancel());
  opening = [];
  root.dataset.opening = 'finished';
}

function playOpening() {
  finishOpening();
  root.dataset.opening = 'playing';
  if (reduced.matches) {
    opening = [identity, hint].map(element => element.animate({ opacity: [0, 1] }, { duration: 200 }));
  } else {
    const ease = 'cubic-bezier(.22, .8, .2, 1)';
    opening = [
      stroke.animate({ strokeDasharray: ['1', '1'], strokeDashoffset: [1, 0] }, { duration: 900, easing: ease }),
      identity.animate({ transform: ['scale(1.272727)', 'scale(1)'] }, { delay: 1100, duration: 500, fill: 'backwards', easing: ease }),
      word.animate({ transform: ['translateY(3.142857px)', 'translateY(0)'] }, { delay: 600, duration: 500, fill: 'backwards', easing: ease }),
      word.animate({ opacity: [0, 1] }, { delay: 600, duration: 180, fill: 'backwards' }),
      hint.animate({ opacity: [0, 1] }, { delay: 1100, duration: 180, fill: 'backwards' })
    ];
  }
  Promise.all(opening.map(animation => animation.finished)).then(finishOpening).catch(() => {});
}

document.querySelector('#appearance').onclick = () => {
  theme = theme === 'system' ? 'light' : theme === 'light' ? 'dark' : 'system';
  appearance();
};
document.querySelector('#replay').onclick = playOpening;
for (const event of ['click', 'contextmenu', 'keydown']) {
  document.addEventListener(event, input => {
    if (root.dataset.opening !== 'playing') return;
    input.preventDefault();
    input.stopImmediatePropagation();
    finishOpening();
  }, true);
}
scheme.addEventListener('change', appearance);
appearance();
document.fonts.ready.then(playOpening);

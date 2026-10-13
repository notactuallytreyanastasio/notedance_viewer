import { makeTour } from "./tour"

export function initHome() {
  makeTour("home", [
    {
      element: "#tour-intro",
      popover: {
        title: "Hi Dave. Here is the whole idea.",
        description:
          "A song lives in three places: the TV you control, the iPads the kids hold, and this page where songs are kept. This walkthrough shows each one.",
        side: "bottom",
        align: "start",
      },
    },
    {
      element: "#import-form",
      popover: {
        title: "Paste a Noteflight link",
        description:
          "Open the score on Noteflight Learning, copy the address from the top of the browser, paste it here and press Import. It takes a few seconds.",
        side: "bottom",
      },
    },
    {
      element: "#btn-example",
      popover: {
        title: "No link handy? Load the example",
        description:
          "Mary Had a Little Lamb for three xylophones. Use it to try the TV and an iPad before class.",
        side: "left",
      },
    },
    {
      element: "#songs",
      popover: {
        title: "Every song has two doors",
        description:
          "“Open on the TV” is yours: play, pause and jump to a measure. “Kids' link” is theirs: pick an instrument and follow the line.",
        side: "top",
      },
    },
    {
      element: "#btn-tour",
      popover: {
        title: "Come back any time",
        description: "This button replays the walkthrough. The TV page and the kids' page each have one too.",
        side: "bottom",
        align: "end",
      },
    },
  ])
}

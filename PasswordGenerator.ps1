# This Azure Function generates a random password by combining three random words from a predefined list.

param(
    $Request,
    $TriggerMetadata
)

# Define a list of words to use for password generation
try {
    $WordList = @(
        'Appl3', 'M0untain', 'R!ver', 'M00n', 'F0rest', '0cean', 'St4r', 'St0ne',
        'B!rd', 'Tre3', 'Fl0wer', 'Cl0ud', 'W!nd', 'Shad0w', 'F!re', 'Cryst4l',
        '3cho', 'Le4f', 'M!rror', 'Dr3am', 'S0und', 'W4ve', 'H!ll', 'V4lley',
        'St0rm', 'Thund3r', 'Ra!n', 'Sn0w', 'Is1and', 'Cany0n', 'Des3rt', 'Pra1rie',
        'Gl4cier', 'V0lcano', 'Gal4xy', 'C0met', 'Met3or', 'Aur0ra',
        'Falc0n', 'E4gle', 'Rav3n', '0wl', 'W0lf', 'F0x', 'B3ar', 'T!ger',
        'L!on', 'P4nda', 'K0ala', '0tter', 'D0lphin', 'Wh4le', 'Sh4rk', 'Turt1e',
        'Drag0n', 'Ph03nix', 'Gr!ffin', 'C0bra', 'G3cko', 'M0ose', 'Badg3r', 'H4wk',
        'Map1e', '0ak', 'P!ne', 'C3dar', 'B!rch', 'W!llow', 'R0se', 'Tul!p',
        'Ivy', 'M0ss', 'F3rn', 'Bamb00', 'Ac0rn', 'M3adow', 'Gr0ve', '0rchard',
        'Em3rald', 'Sapph!re', 'Rub1', '0pal', 'J4de', 'Amb3r', 'S!lver', 'G0ld',
        'C0pper', 'Gran!te', 'Marb1e', 'Qu4rtz', 'P3arl', 'T0paz', '0nyx', 'Jasp3r',
        'S0lar', 'Lun4r', '0rbit', 'N3bula', 'C0smos', 'Pl4net', 'Saturn', 'V3nus',
        'M4rs', 'Jup!ter', 'M3rcury', 'Plut0', 'Ast3roid', 'Ecl!pse', 'Zen!th', 'N0va',
        'Br33ze', 'Fr0st', 'M!st', 'F0g', 'H4il', 'Temp3st', 'Cycl0ne', 'T0rnado',
        'Sunr!se', 'Suns3t', 'Tw!light', 'D4wn', 'Dusk', 'Skyl!ne', 'H0rizon', 'R4inbow',
        'Cast1e', 'T0wer', 'Br!dge', 'Harb0ur', 'L!ghthouse', 'Cab!n', 'C0ttage', 'Temp1e',
        'F0rtress', 'Pal4ce', 'G4rden', 'F0untain', 'Gatew4y', 'Tunn3l', 'Tra!l', 'P4th',
        'C0mpass', 'Anch0r', 'Lantern', 'T0rch', 'B3acon', 'Sh!eld', 'Cr0wn', 'K3y',
        'L0cket', 'Scr0ll', 'B00k', 'Qu!ll', 'C4ndle', 'Cl0ck', 'G3ar', 'Ham3r',
        'V0yager', 'Rang3r', 'Sc0ut', 'P!lot', 'Sail0r', 'N0mad', 'Trav3ller', 'P!oneer',
        'Expl0rer', 'Guard!an', 'Hunt3r', 'Arch3r', 'Kn!ght', 'W!zard', 'R0ver', 'Capt4in',
        'J0urney', 'Adv3nture', 'Disc0very', 'Myst3ry', 'S3cret', 'Leg3nd', 'Myth!c', 'W0nder',
        'Sp!rit', 'C0urage', 'H0nour', 'V!ctory', 'F0rtune', 'Dest!ny', 'Fre3dom', 'L3gacy'
    )

    # Select three random words from the list and concatenate them to form the password
    $Words = Get-Random -InputObject $WordList -Count 3
    # Join the selected words to create the final password
    $GeneratedPassword = $Words -join ''

    # Return the generated password as the HTTP response
    Push-OutputBinding -Name Response -Value @{ StatusCode = 200; Body = $GeneratedPassword }
}
catch {
    Push-OutputBinding -Name Response -Value @{ StatusCode = 500; Body = "Error generating password: $($_.Exception.Message)" }
}
local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Paladin-Holy','Unknown-Unknown','Warrior-Protection','Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Paladin-Retribution','Rogue-Assassination','Warrior-Arms','Mage-Frost','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECoEWAAIBAAgKQRxlQQCCAgABAAgKQRxlQQCCAgAAAA==.Accar:BAAANQAECgcIEAAAAA==.Achu:BAAANQAECgUIBwABNQAECgkJKQACAOYhAA==.Acylies:BAAANQADCgUICAAAAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECoEaAAMDAAkKyRu1LACWAgADAAkKyRu1LACWAgAEAAEK1QbtegAiAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Alindriel:BAAANQADCgMIAwAAAA==.Althea:BAABNQAECoEYAAIFAAgKrRf2QQA/AgAFAAgKrRf2QQA/AgAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQADCgYIBgAGAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAGAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgQICgAGAAAAAA==.',
Au='Aubury:BAAANQADCgEIAQABNQADCgQIBAAGAAAAAA==.',
Av='Aviendha:BAAANQADCgYIBgAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Ba='Barricade:BAABNQAECoEaAAIHAAcKyRdrEgDRAQAHAAcKyRdrEgDRAQAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgYIEAAGAAAAAA==.Bcwarrior:BAAANQAECgYIEAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAAANQAECgQIDwAAAA==.',
Bl='Blizzaga:BAABNQAECoEmAAICAAgK+xNDSQCzAQACAAgK+xNDSQCzAQAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAGAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQADCgQIBAAGAAAAAA==.Brocephus:BAAANQAECgQIBwAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgIJAgAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECoEbAAMIAAkKJiJHCwCPAQAJAAYKiSLvSABaAgAIAAQKECJHCwCPAQABNQAECgkJKQACAOYhAA==.Clõüd:BAACNQAFFIEGAAMKAAMKmw5bBwC/AAAKAAMKVw5bBwC/AAALAAIKEw86HgCQAAA1AAQKgToAAwsACQo0IgYgACwDAAsACQo0IgYgACwDAAoABwrOGd8VACkCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgYICwAAAA==.',
De='Demonicspeak:BAAANQAECgYICgAAAA==.Densepancake:BAAANQAECgUIDQAAAA==.',
Di='Dianeneedrol:BAAANQAECgUIDQAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAMIBgAKAJsOAA==.',
Do='Dotzillah:BAAANQADCgIIAgAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAGAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECoElAAMFAAkKTQ0aUAALAgAFAAkKTQ0aUAALAgALAAYK+QJgGQG9AAAAAA==.Ellex:BAAANQAECgEIAQAAAA==.Ellexstrasza:BAAANQADCgUIBgABNQAECgEIAQAGAAAAAA==.',
En='Enhancdepeen:BAAANQADCggICAAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAAANQAECgUICgAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgYIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECoEYAAIMAAkKxyEcDQD/AgAMAAkKxyEcDQD/AgAAAA==.',
Go='Gonamanar:BAAANQAECgYIDAAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAAANQAECgYIEgABNQAECgkJHQANAHMcAA==.',
Ha='Happyhour:BAABNQAECoEYAAMOAAcKGwbyKACIAAAPAAQKwAQ+aQG8AAAOAAMK6gfyKACIAAAAAA==.Harryportals:BAAANQADCgUIBQAAAA==.',
He='Hexidecimal:BAAANQAECgcIEQAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgQIBgAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAAANQAECgUICQAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAAANQAECggIEQABNQAECgkJMwAPABckAA==.Holylock:BAAANQAECgIIBQAAAA==.Holymage:BAABNQAECoEzAAIPAAkKFyQ6CgCqAwAPAAkKFyQ6CgCqAwAAAA==.Holyseeker:BAABNQAECoEZAAMLAAcKsh8tVQBtAgALAAcKsh8tVQBtAgAFAAEKvgnYAgE7AAABNQAECgkJMwAPABckAA==.Holyshaman:BAAANQAECgQICAAAAA==.Holywarrior:BAAANQAECgcIEwAAAA==.Holyymonk:BAAANQAECgIIBQAAAA==.Holyyseeker:BAAANQAECgcIEAAAAA==.Hottamalie:BAAANQAECgQIEwAAAA==.',
Ia='Iampally:BAABNQAECoEbAAIKAAgKTh0fDgCVAgAKAAgKTh0fDgCVAgAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIDQABNQAECgkJIgAFABwgAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.',
Ke='Keg:BAACNQAFFIEWAAIQAAYKOSYrAAC2AgAQAAYKOSYrAAC2AgA1AAQKgSIAAhAACQrhJk8AAPMDABAACQrhJk8AAPMDAAAA.',
Ki='Kittyhawk:BAAANQAECggIEwAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECoEdAAIRAAgKhxCGGQD7AQARAAgKhxCGGQD7AQAAAA==.',
Ku='Kuromeow:BAABNQAECoEiAAIPAAkKFxn8WAC8AgAPAAkKFxn8WAC8AgAAAA==.',
La='Larake:BAAANQAECgUIDwAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAAANQAECgQICAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAECgkJHQANAHMcAA==.',
Lo='Lockinaround:BAAANQAECgQICgAAAA==.',
Ma='Manaplague:BAAANQAECgEIAQAAAA==.Marleau:BAAANQAECgQIDwAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECoEaAAMLAAgKjCGYLwDsAgALAAgKjCGYLwDsAgAKAAMKxhK8SwCPAAAAAA==.Meruk:BAAANQAECgYICwAAAA==.Mesoholy:BAAANQAECgQICAAAAA==.',
Mk='Mk:BAEANQAECgQIBAAAAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECoEhAAMSAAkKxBuLFACrAgASAAgK5hyLFACrAgATAAYK7hcAAAAAAAAAAA==.',
No='Noideea:BAABNQAECoEoAAINAAkKHyFrFQBaAwANAAkKHyFrFQBaAwAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAAANQAECgUIDgAAAA==.',
Om='Omie:BAAANQAECgYIEgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Qi='Qilin:BAAANQADCgMIAwAAAA==.',
Ra='Raythe:BAAANQAECggIDAAAAA==.Razzeman:BAAANQABCgYIBgAAAA==.',
Re='Reverend:BAAANQADCgQIBAAAAA==.',
Ru='Ruck:BAAANQAECgEJAQABNQAECgcIEAAGAAAAAA==.Rucker:BAAANQAECgcIEAAAAA==.Ruckkin:BAAANQADCgUIBQABNQAECgcIEAAGAAAAAA==.Rucksy:BAAANQAECgQICwABNQAECgcIEAAGAAAAAA==.',
Ry='Ryan:BAABNQAECoEVAAMLAAYKAR1orgCKAQALAAUKbx5orgCKAQAFAAQKgx/lhQBgAQAAAA==.',
Se='Senchá:BAABNQAECoEZAAIUAAgKgyT+AgBhAwAUAAgKgyT+AgBhAwABNQAECggIJQAQAEcfAA==.Seraphae:BAAANQAECgUIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECgUIBQAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Sheong:BAABNQAECoElAAIQAAgKRx8DCACVAgAQAAgKRx8DCACVAgAAAA==.Shèrlock:BAAANQAECgcIEwAAAA==.',
Si='Silverfox:BAAANQAECgcIDwABNQAECgkJIgAFABwgAA==.',
Sk='Skera:BAAANQAECgcIEAAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAAANQAECgYIDgAAAA==.Skye:BAAANQAECgUIBwAAAA==.',
Sl='Sleepysniper:BAABNQAECoEbAAIVAAgKgx8sEADWAgAVAAgKgx8sEADWAgABNQAECgkJKAANAB8hAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAECgkJHQANAHMcAA==.',
Ss='Ssgtusmc:BAABNQAECoEdAAIHAAcK/QKfJgDbAAAHAAcK/QKfJgDbAAAAAA==.Ssjgodxx:BAABNQAECoEXAAINAAkKzBRzXQBXAgANAAkKzBRzXQBXAgABNQAECgkJIQASAMQbAA==.',
St='Stargasm:BAABNQAECoE3AAIDAAgKmBc+TwAMAgADAAgKmBc+TwAMAgAAAA==.',
Sw='Swiftmend:BAAANQAECgUICgABNQAECgkJHQANAHMcAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCgEIAQAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timewing:BAABNQAECoEeAAMWAAkK3A/tFwAkAgAWAAkK3A/tFwAkAgAXAAEKPg4nIQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECgUICAAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAAANQABCgQIBAAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAAANQAECgQIDAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAAANQAECggIDwAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgIIAgABNQAECgQIBAAGAAAAAA==.',
Xi='Xiaobao:BAAANQAECgUICgAAAA==.Xiaoduoduo:BAABNQAECoEiAAQFAAkKHCBYCwBfAwAFAAkKHCBYCwBfAwALAAUKFSL4gAD2AQAKAAIKGyFSQgDCAAAAAA==.Xiaomak:BAABNQAECoEdAAMBAAkKOSGHFwAkAwABAAkKOSGHFwAkAwAVAAUKNQ9+PwAmAQABNQAECgkJIgAFABwgAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECgcIHAALAEUYAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAFALgkAA==.Zeroskills:BAABNQAECoElAAIRAAgKgwlbHQDTAQARAAgKgwlbHQDTAQAAAA==.',
Zu='Zulinar:BAAANQAECgUIDgAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgcIDQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
